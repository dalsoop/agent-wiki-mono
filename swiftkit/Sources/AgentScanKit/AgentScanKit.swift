import Foundation

/// 지금 도는 claude/codex CLI 세션을 잡아 "누가 무엇을 만지나"를 안다 — 여러 에이전트
/// 관제 앱(devtools-hub·agent-control-plane 등)이 공유하는 단일 구현.
/// `ps` 로 프로세스, `lsof` 로 각 프로세스의 cwd 를 얻어 앱 슬러그로 귀속하고,
/// 확장 모드(cwd=저장소 루트)는 세션 트랜스크립트 tail 로 최근 편집 앱을 추론한다.
public struct RunningAgent: Sendable, Codable, Equatable, Identifiable {
    public var pid: Int32
    public var kind: String       // "claude" | "codex"
    public var cwd: String
    public var elapsed: String    // ps etime
    public var appSlug: String?   // cwd 가 개별 앱 디렉터리(apps/<x>, x≠*-mono)일 때 그 x
    public var repo: String?      // cwd 가 속한 *-mono 저장소
    public var recentApps: [String]  // 트랜스크립트 tail 로 추론한 최근 편집 앱(추정)
    public var id: Int32 { pid }

    public init(pid: Int32, kind: String, cwd: String, elapsed: String,
                appSlug: String?, repo: String?, recentApps: [String]) {
        self.pid = pid
        self.kind = kind
        self.cwd = cwd
        self.elapsed = elapsed
        self.appSlug = appSlug
        self.repo = repo
        self.recentApps = recentApps
    }
}

public struct AgentScanner: Sendable {
    public init() {}

    public func scan() -> [RunningAgent] {
        let lines = Self.run("/bin/ps", ["-axww", "-o", "pid=,etime=,command="])
        var out: [RunningAgent] = []
        for line in lines {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard let sp = t.firstIndex(of: " "), let pid = Int32(t[t.startIndex..<sp]) else { continue }
            let rest = t[t.index(after: sp)...].trimmingCharacters(in: .whitespaces)
            guard let sp2 = rest.firstIndex(of: " ") else { continue }
            let elapsed = String(rest[rest.startIndex..<sp2])
            let command = String(rest[rest.index(after: sp2)...])
            guard let kind = Self.kind(command) else { continue }
            let cwd = Self.cwd(of: pid) ?? ""
            guard cwd != "/" && !cwd.isEmpty else { continue }
            out.append(RunningAgent(
                pid: pid, kind: kind, cwd: cwd, elapsed: elapsed,
                appSlug: Self.appSlug(cwd), repo: Self.repo(cwd),
                recentApps: Self.recentApps(cwd: cwd)))
        }
        return out
    }

    // MARK: - 순수 헬퍼(테스트 대상)

    /// 커맨드가 claude/codex 에이전트인지 — GUI 앱·MCP 래퍼·확장 백엔드(app-server) 제외.
    public static func kind(_ command: String) -> String? {
        let l = command.lowercased()
        if l.contains(".app/contents/") || l.contains("app-server") { return nil }
        if l.contains("mcp") && !l.contains("claude ") && !l.contains("codex ") { return nil }
        if l.range(of: #"(^|/)claude(\s|$)"#, options: .regularExpression) != nil { return "claude" }
        if l.range(of: #"(^|/)codex(\s|$)"#, options: .regularExpression) != nil { return "codex" }
        return nil
    }

    /// cwd 가 **개별 앱 디렉터리**를 가리킬 때만 그 슬러그(`apps/<x>`, x≠`*-mono`).
    public static func appSlug(_ cwd: String) -> String? {
        let p = cwd.split(separator: "/").map(String.init)
        guard let i = p.firstIndex(of: "apps"), i + 1 < p.count else { return nil }
        return p[i + 1].hasSuffix("-mono") ? nil : p[i + 1]
    }

    public static func repo(_ cwd: String) -> String? {
        cwd.split(separator: "/").map(String.init).first { $0.hasSuffix("-mono") }
    }

    /// 세션 트랜스크립트 tail 로 최근 만진 앱 슬러그(빈도순). claude 는 cwd 를 `-` 로
    /// 인코딩한 `~/.claude/projects/<encoded>/` 아래 최근 jsonl 마지막 128KB 를 본다.
    public static func recentApps(cwd: String, maxTailBytes: Int = 128 * 1024, top: Int = 6) -> [String] {
        let encoded = cwd.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ".", with: "-")
        let dir = (NSHomeDirectory() as NSString).appendingPathComponent(".claude/projects/\(encoded)")
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: dir) else { return [] }
        let newest = files.filter { $0.hasSuffix(".jsonl") }
            .map { (dir as NSString).appendingPathComponent($0) }
            .compactMap { p -> (String, Date)? in
                guard let m = (try? fm.attributesOfItem(atPath: p))?[.modificationDate] as? Date else { return nil }
                return (p, m)
            }
            .max { $0.1 < $1.1 }?.0
        guard let newest, let handle = FileHandle(forReadingAtPath: newest) else { return [] }
        defer { do { try handle.close() } catch {} }
        do {
            let end = try handle.seekToEnd()
            try handle.seek(toOffset: end > UInt64(maxTailBytes) ? end - UInt64(maxTailBytes) : 0)
        } catch {}
        let readData: Data
        do {
            readData = try handle.readToEnd() ?? Data()
        } catch {
            readData = Data()
        }
        let text = String(decoding: readData, as: UTF8.self)
        var counts: [String: Int] = [:]
        let ns = text as NSString
        try? NSRegularExpression(pattern: #"/apps/([A-Za-z0-9._-]+)"#)
            .enumerateMatches(in: text, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
                guard let m, m.numberOfRanges > 1 else { return }
                let slug = ns.substring(with: m.range(at: 1))
                guard !slug.hasSuffix("-mono") else { return }
                counts[slug, default: 0] += 1
            }
        return counts.sorted { $0.value > $1.value }.prefix(top).map(\.key)
    }

    // MARK: - 프로세스 실행(파이프 데드락·행 방지)

    private final class DataHolder: @unchecked Sendable { var data = Data() }

    private static func cwd(of pid: Int32) -> String? {
        run("/usr/sbin/lsof", ["-a", "-p", "\(pid)", "-d", "cwd", "-Fn"])
            .first { $0.hasPrefix("n") }.map { String($0.dropFirst()) }
    }

    static func run(_ path: String, _ args: [String]) -> [String] {
        #if os(macOS)
        guard FileManager.default.isExecutableFile(atPath: path) else { return [] }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return [] }
        // 읽기를 백그라운드에서 먼저 — 파이프 버퍼(64KB)가 차도 데드락되지 않게(ps 출력이 큼).
        // 워치독: 매달리면 3초 후 강제 종료.
        let holder = DataHolder()
        let group = DispatchGroup(); group.enter()
        DispatchQueue.global().async {
            holder.data = pipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        if group.wait(timeout: .now() + 3) == .timedOut { p.terminate(); return [] }
        p.waitUntilExit()
        return String(decoding: holder.data, as: UTF8.self).split(separator: "\n").map(String.init)
        #else
        []
        #endif
    }
}
