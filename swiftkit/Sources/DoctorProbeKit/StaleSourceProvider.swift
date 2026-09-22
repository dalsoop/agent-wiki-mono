import Foundation
import InteropKit

// MARK: - 설치본 신선도 (app-fleet-doctor 부착)

/// `path-cli-health stale-source` 가 잡은, 번들이 origin/main 최신 소스보다 뒤처진
/// 앱들을 doctor 한 스캔에 끌어온다.
///
/// path-cli-health 는 별개 앱이고, 이 provider 는 설치된 `path-cli-health
/// stale-source --json` CLI 를 **소비만** 한다(Core 를 링크하지 않는 느슨한 결합) —
/// `ReachWatchDoctorProvider` 와 같은 결합 방식. 2026-08-09: LaunchAgent 로 따로
/// 돌리는 대신 doctor 에 붙이기로 했다 — 관측 지점을 하나로 모은다.
///
/// 앱당 finding 을 쏟으면 doctor 가 잠기므로, **요약 1건**(개수 + 예시 몇 개 +
/// path-cli-health 로 연결)만 올린다. 앱별 상세는 `path-cli-health stale-source`.
public struct StaleSourceDoctorProvider: DoctorProvider {
    public let id = "stale-source"

    private let pathRoots: [String]
    private let resolveOnPath: @Sendable (String, [String]) -> String?
    private let runCLI: @Sendable (String, [String], TimeInterval) -> (exit: Int32, stdout: String)
    private let pullExternalReports: Bool

    public init(
        pathRoots: [String] = [HostPlatform.homebrewBin, "/usr/local/bin"],
        resolveOnPath: (@Sendable (String, [String]) -> String?)? = nil,
        runCLI: (@Sendable (String, [String], TimeInterval) -> (exit: Int32, stdout: String))? = nil,
        pullExternalReports: Bool = true
    ) {
        self.pathRoots = pathRoots
        self.resolveOnPath = resolveOnPath ?? Self.defaultResolve
        self.runCLI = runCLI ?? Self.defaultRunCLI
        self.pullExternalReports = pullExternalReports
    }

    public func run() async -> [DoctorFinding] {
        guard pullExternalReports else { return [] }
        // path-cli-health 미설치면 이 축은 조용히 생략(다른 provider 들과 같은 관례).
        guard resolveOnPath("path-cli-health", pathRoots) != nil else { return [] }
        // git fetch·merge-base IO 라 fast 점검보다 느리다 — 90초 상한(함대 규모 고려).
        let (code, stdout) = runCLI("path-cli-health", ["stale-source", "--json"], 90)
        return StaleSourceReportMapper.map(stdout: stdout, exitCode: code, source: id)
    }

    // MARK: Defaults — ReachWatchDoctorProvider 와 같은 Foundation.Process seam.

    private static func defaultResolve(cli: String, roots: [String]) -> String? {
        for root in roots {
            let p = (root as NSString).appendingPathComponent(cli)
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        let (code, out) = defaultRunCLI("/usr/bin/which", [cli], 5)
        if code == 0 {
            let p = out.trimmingCharacters(in: .whitespacesAndNewlines)
            if !p.isEmpty { return p }
        }
        return nil
    }

    package static func defaultRunCLI(
        _ exe: String,
        _ args: [String],
        _ timeout: TimeInterval
    ) -> (exit: Int32, stdout: String) {
        let p = Process()
        if exe.contains("/") {
            p.executableURL = URL(fileURLWithPath: exe)
            p.arguments = args
        } else {
            p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            p.arguments = [exe] + args
        }
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        do {
            try p.run()
            let item = DispatchWorkItem { p.terminate() }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: item)
            let data = out.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            item.cancel()
            return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
        } catch {
            return (127, "")
        }
    }
}

// MARK: - Report mapper (pure, testable)

/// `path-cli-health stale-source --json` 출력을 doctor finding 으로.
///
/// reach-watch 와 달리 `{ok,result}` 봉투가 아니라 **맨 배열**이다 — hit 이 없으면
/// `[]`(exit 0), 있으면 그 목록(exit 1). exitCode 는 참고만 하고 배열 유무로 판단한다
/// (127 = path-cli-health 실행 실패 — 조용히 생략, exit 1 은 "정상적으로 hit 있음"이라
/// 실패로 보면 안 된다).
package enum StaleSourceReportMapper {
    package static func map(stdout: String, exitCode: Int32, source: String) -> [DoctorFinding] {
        guard exitCode != 127,
              let data = stdout.data(using: .utf8),
              let arr = ProbeJSON.array(from: data)
        else { return [] }

        let hits = arr.compactMap { StaleHit($0) }
        return summary(hits: hits, source: source)
    }

    private static func summary(hits: [StaleHit], source: String) -> [DoctorFinding] {
        if hits.isEmpty {
            return [DoctorFinding(
                category: .staleSource,
                severity: .ok,
                body: .init(
                    subject: "stale-source",
                    title: "설치본 신선도 통과",
                    detail: "path-cli-health 가 확인한 설치본 전부 origin/main 최신"
                ),
                source: source
            )]
        }
        let examples = hits.prefix(5).map(\.name).joined(separator: ", ")
        let more = hits.count > 5 ? " 외 \(hits.count - 5)개" : ""
        return [DoctorFinding(
            category: .staleSource,
            severity: .warn,
            body: .init(
                subject: "stale-source",
                title: "설치본 \(hits.count)개가 origin/main 뒤처짐",
                detail: "예: \(examples)\(more)",
                remedy: "path-cli-health stale-source 로 전체 목록·재설치 명령 확인, 또는 gujo-cloud-apps fleet update --stale-only"
            ),
            source: source,
            payload: [
                "owner": "path-cli-health",
                "count": "\(hits.count)",
                "apps": hits.map(\.name).joined(separator: ","),
            ]
        )]
    }

    private struct StaleHit {
        let name: String
        init?(_ raw: [String: Any]) {
            guard let name = raw["name"] as? String else { return nil }
            self.name = name
        }
    }
}
