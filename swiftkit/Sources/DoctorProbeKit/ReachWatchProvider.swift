import Foundation
import InteropKit

// MARK: - 에이전트 도달 감시 (app-fleet-doctor 부착)

/// `agent-reach-watch` 가 당긴 도달 분포/갭을 doctor 한 스캔에 끌어온다.
///
/// reach-watch 는 별개 앱이고, 이 provider 는 설치된 `agent-reach-watch scan --json`
/// CLI 를 **소비만** 한다(Core 를 링크하지 않는 느슨한 결합). 설계 정본:
/// docs/agent-fleet/agent-reach-watch.md ("ATTACHES to app-fleet-doctor").
///
/// 도달은 "존재 ≠ 도달" — 모노레포에 있는 앱이 에이전트에게 실제로 닿았는지 4개 인자
/// (registry 등록 · capabilities 응답 · agent surface 부착 · StateMirror 게시)로 판정한다.
/// 앱당 finding 을 쏟으면 수백 건이 돼 doctor 가 잠기므로, **fleet 요약 1건**(분포 +
/// 지배적 갭 + reach-watch 로 연결)만 올린다. 앱별 상세는 `agent-reach-watch scan`.
public struct ReachWatchDoctorProvider: DoctorProvider {
    public let id = "reach-watch"

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
        // reach-watch 가 설치돼 있을 때만 — 없으면 이 축은 조용히 생략(다른 provider 들이
        // 각자의 설치 검사를 따로 둔다).
        guard resolveOnPath("agent-reach-watch", pathRoots) != nil else { return [] }
        let (code, stdout) = runCLI("agent-reach-watch", ["scan", "--json"], 45)
        return ReachWatchReportMapper.map(stdout: stdout, exitCode: code, source: id)
    }

    // MARK: Defaults — ManagementAppsDoctorProvider 와 같은 Foundation.Process seam.

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
        // exe 에 / 없으면 PATH 로(env). 있으면 절대경로 직접.
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

/// `agent-reach-watch scan --json` 의 `{ok, result:{...}}` 를 doctor finding 으로.
///
/// `ReachReport.gaps` 는 연산 프로퍼티라 JSON 에 직렬화되지 않으므로 `apps` 에서
/// 다시 계산한다(grade != reached, 점수 오름차순). JSONSerialization(느슨한 파싱)을
/// 써서 reach-watch Core 타입을 링크하지 않는다.
package enum ReachWatchReportMapper {
    package static func map(stdout: String, exitCode: Int32, source: String) -> [DoctorFinding] {
        guard let data = stdout.data(using: .utf8),
              let obj = ProbeJSON.object(from: data)
        else { return [] }

        // {ok, result} 봉투; ok:false 면 도구가 스스로 실패를 보고한 것 — 조용히 생략.
        if let ok = obj["ok"] as? Bool, ok == false { return [] }
        let root = (obj["result"] as? [String: Any]) ?? obj
        let apps = (root["apps"] as? [[String: Any]]) ?? []
        let fleetSize = (root["fleetSize"] as? Int) ?? apps.count

        let gaps = apps.compactMap { ReachApp($0) }
            .filter { $0.grade != "reached" }
            .sorted { $0.score < $1.score }

        return summary(gaps: gaps, fleetSize: fleetSize, source: source)
    }

    private static func summary(gaps: [ReachApp], fleetSize: Int, source: String) -> [DoctorFinding] {
        if gaps.isEmpty {
            return [DoctorFinding(
                category: .reach,
                severity: .ok,
                body: .init(
                    subject: "reach",
                    title: "함대 도달 통과",
                    detail: "보고된 \(fleetSize)개 앱 전부 도달(reached)"
                ),
                source: source
            )]
        }
        let unreached = gaps.filter { $0.grade == "unreached" }.count
        let partial = gaps.filter { $0.grade == "partial" }.count
        let reached = max(0, fleetSize - gaps.count)

        // 지배적 빠진 인자 — 전 함대에서 가장 많이 빠진 도달 축. 한 곳을 고치면 갭이 줄든다.
        var missCount: [String: Int] = [:]
        for g in gaps { for m in g.missing { missCount[m, default: 0] += 1 } }
        let dominant = missCount.max { $0.value < $1.value }
            .map { "\($0.key) (\($0.value)앱)" } ?? "—"

        let severity: DoctorSeverity = unreached > 0 ? .fail : .warn
        return [DoctorFinding(
            category: .reach,
            severity: severity,
            body: .init(
                subject: "reach",
                title: "에이전트 도달 갭 \(gaps.count)/\(fleetSize) — 미도달 \(unreached), 부분 \(partial)",
                detail: "reached \(reached) / partial \(partial) / unreached \(unreached). 가장 많이 빠진 인자: \(dominant)",
                remedy: "agent-reach-watch scan 으로 앱별 갭 확인. 보통 agent surface(skills) 부착 부재가 지배적."
            ),
            source: source,
            payload: [
                "owner": "agent-reach-watch",
                "fleetSize": "\(fleetSize)",
                "reached": "\(reached)",
                "partial": "\(partial)",
                "unreached": "\(unreached)",
                "dominantGap": dominant,
            ]
        )]
    }

    /// reach-watch AppReach JSON 을 값으로 가둔 파싱 헬퍼.
    private struct ReachApp {
        let app: String
        let grade: String
        let score: Double
        let missing: [String]
        init?(_ raw: [String: Any]) {
            guard let app = raw["app"] as? String else { return nil }
            self.app = app
            self.grade = (raw["grade"] as? String) ?? "unreached"
            self.score = (raw["score"] as? Double) ?? 0
            // missingFactors 는 Set<ReachFactor> → JSON 문자열 배열.
            if let arr = raw["missingFactors"] as? [String] {
                self.missing = arr
            } else if let arr = raw["missingFactors"] as? [Any] {
                self.missing = arr.compactMap { $0 as? String }
            } else {
                self.missing = []
            }
        }
    }
}
