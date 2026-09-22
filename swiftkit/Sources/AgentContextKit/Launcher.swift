import Foundation
import AgentSessionKit

/// 에이전트를 **컨텍스트를 기록한 뒤** 실행하는 래퍼.
///
/// 설계 조건은 하나다 — 에이전트 실행을 방해하지 않는다. 기록에 실패해도 실행은 진행하고,
/// 기록이 끝나면 `execv` 로 자기 프로세스를 에이전트로 갈아치운다. fork+wait 이 아니라 exec 인
/// 이유는 TTY·시그널·job control 을 원본 그대로 남기기 위해서다(중간 프로세스가 끼면
/// Ctrl-C·창 크기 변경·raw mode 가 미묘하게 어긋난다).
public struct Launcher: Sendable {
    public let resolver: ContextResolver
    public let store: LaunchStore

    public init(resolver: ContextResolver = ContextResolver(), store: LaunchStore = LaunchStore()) {
        self.resolver = resolver
        self.store = store
    }

    /// 실행 전 계획. 세션이 아직 없어도 답할 수 있다 — 탐색이 결정적이기 때문이다.
    public struct Plan: Sendable {
        public let tool: AgentTool
        public let cwd: String
        public let docs: [InjectedDoc]
        /// 발급할(또는 발급된) 세션 id. 런타임이 지정을 지원할 때만 채워진다.
        public let sessionId: String?
        public var approxTokens: Int { docs.compactMap(\.approxTokens).reduce(0, +) }
    }

    public func plan(tool: AgentTool, cwd: String, sessionId: String? = nil) -> Plan {
        Plan(tool: tool, cwd: cwd, docs: resolver.resolve(tool: tool, cwd: cwd), sessionId: sessionId)
    }

    /// 런타임이 세션 id 를 **미리 지정**할 수 있는가.
    ///
    /// Claude 는 `--session-id <uuid>` 를 받는다. 그래서 래퍼가 id 를 발급하고 그 id 로
    /// 기록하면 세션과 기록이 추측 없이 정확히 이어진다. Codex·Grok 은 그 자리가 없어
    /// cwd + 시작시각으로만 맞출 수 있는데, Codex 는 애초에 주입 원문을 로그에 남기므로
    /// 래퍼가 필요 없다.
    ///
    /// **설치된 CLI 의 `--help` 를 실제로 물어본다.** 플래그는 버전마다 생기고 사라지는데,
    /// 하드코딩하면 남의 맥에서 조용히 틀린다 — 없는 플래그를 붙여 실행 자체가 죽거나,
    /// 있는데도 기록을 포기한다. 프로세스를 띄우므로 결과를 캐시하고, 못 물어보면
    /// 알려진 기본값으로 물러난다.
    public static func supportsPresetSessionID(_ tool: AgentTool) -> Bool {
        if let cached = probeCache.value(for: tool) { return cached }
        let result = probePresetSessionID(tool) ?? (tool == .claude)
        probeCache.set(result, for: tool)
        return result
    }

    /// `<tool> --help` 에 `--session-id` 가 **플래그 자리**로 있는지 본다. 못 물어보면 nil.
    ///
    /// 단순 부분 문자열 검색은 못 쓴다 — 다른 플래그 설명문이 `--session-id` 를 언급하기만
    /// 해도 지원한다고 오판한다(실제로 grok `--fork-session` 설명이 그렇다).
    /// 그래서 줄 앞머리가 그 플래그인 경우만 인정한다.
    static func probePresetSessionID(_ tool: AgentTool, timeout: TimeInterval = 5) -> Bool? {
        guard let path = which(tool.executable) else { return nil }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = ["--help"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        guard (try? p.run()) != nil else { return nil }

        // help 가 안 끝나는 CLI 가 있다(dual-entry hang 전례). 기다리다 세션을 잡아먹지 않는다.
        let deadline = Date().addingTimeInterval(timeout)
        while p.isRunning, Date() < deadline { usleep(50_000) }
        if p.isRunning { p.terminate(); return nil }

        guard let data = try? pipe.fileHandleForReading.readToEnd(),
              let text = String(data: data ?? Data(), encoding: .utf8) else { return nil }
        return Self.declaresSessionIDFlag(in: text)
    }

    /// help 텍스트가 `--session-id` 를 **플래그로 선언**하는가.
    /// `--session-id …` 또는 `-s, --session-id …` 로 줄이 시작할 때만 인정한다.
    static func declaresSessionIDFlag(in help: String) -> Bool {
        for rawLine in help.components(separatedBy: .newlines) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            // 짧은 별칭이 앞에 붙는 형태를 벗겨낸다: `-s, --session-id <ID>`
            if line.hasPrefix("-"), let comma = line.firstIndex(of: ","), line.distance(from: line.startIndex, to: comma) <= 3 {
                line = String(line[line.index(after: comma)...]).trimmingCharacters(in: .whitespaces)
            }
            if line.hasPrefix("--session-id") { return true }
        }
        return false
    }

    /// 프로브 결과 캐시 — 한 프로세스 수명 동안 CLI 를 한 번만 띄운다.
    private final class ProbeCache: @unchecked Sendable {
        private let lock = NSLock()
        private var store: [AgentTool: Bool] = [:]
        func value(for tool: AgentTool) -> Bool? { lock.withLock { store[tool] } }
        func set(_ value: Bool, for tool: AgentTool) { lock.withLock { store[tool] = value } }
    }
    private static let probeCache = ProbeCache()

    /// 실행 파일 이름과 인자를 조립한다. 세션 id 를 지정할 수 있으면 끼워 넣는다.
    public static func argv(tool: AgentTool, userArgs: [String], sessionId: String?) -> [String] {
        var out = [tool.executable]
        if let sessionId, supportsPresetSessionID(tool), !userArgs.contains("--session-id"),
           !userArgs.contains("--resume"), !userArgs.contains("-r"), !userArgs.contains("--continue") {
            out += ["--session-id", sessionId]
        }
        return out + userArgs
    }

    /// 기록 후 `exec`. 성공하면 **돌아오지 않는다**.
    ///
    /// - Returns: exec 자체가 실패했을 때만 반환(errno 메시지).
    public func recordAndExec(tool: AgentTool, cwd: String, userArgs: [String],
                             dryRun: Bool = false) -> String {
        let sessionId = Self.supportsPresetSessionID(tool) ? UUID().uuidString.lowercased() : nil
        let plan = plan(tool: tool, cwd: cwd, sessionId: sessionId)
        let full = Self.argv(tool: tool, userArgs: userArgs, sessionId: sessionId)

        // 기록 실패는 실행을 막지 않는다 — 관측 도구가 작업을 인질로 잡으면 안 된다.
        if let sessionId {
            do {
                try store.record(sessionId: sessionId, tool: tool, cwd: cwd, argv: full, docs: plan.docs)
            } catch {
                FileHandle.standardError.write(Data("warn: 컨텍스트 기록 실패(실행은 계속): \(error)\n".utf8))
            }
        }

        if dryRun { return "" }
        return Self.exec(full)
    }

    /// PATH 에서 찾아 `execv`. 성공하면 반환하지 않는다.
    static func exec(_ argv: [String]) -> String {
        guard let program = argv.first else { return "빈 명령" }
        guard let path = which(program) else { return "PATH 에 없음: \(program)" }

        // execv 는 C 배열을 요구한다. 각 인자를 strdup 해 수명을 프로세스 이미지 교체까지 유지한다.
        var cArgs: [UnsafeMutablePointer<CChar>?] = argv.map { strdup($0) }
        cArgs.append(nil)
        execv(path, &cArgs)
        return "exec 실패: \(String(cString: strerror(errno)))"
    }

    /// PATH 순회. `which` 를 프로세스로 부르지 않는다(래퍼 지연을 늘리지 않으려고).
    public static func which(_ program: String, fm: FileManager = .default) -> String? {
        if program.contains("/") { return fm.isExecutableFile(atPath: program) ? program : nil }
        for dir in (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":") {
            let candidate = String(dir) + "/" + program
            if fm.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }
}
