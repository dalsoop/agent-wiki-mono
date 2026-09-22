import Foundation
import InteropKit

// MARK: - 자격 도달 (app-fleet-doctor 부착)

/// `agent-vault consumers --json` 을 doctor 한 스캔에 끌어온다.
///
/// **왜 필요한가.** 도달 4인자(registry 등록·capabilities 응답·agent surface·StateMirror)는
/// "에이전트가 앱을 찾는 통로" 를 잰다. 그런데 "앱이 자격에 닿는가" 는 아무도 안 봤다.
/// 2026-08-11 실측: 함대 18개 앱이 `app:<슬러그>@macbook` 을 상수로 박았고 **12개가
/// 등록되지 않은 agentID** 를 불러 자격 조회가 전부 죽어 있었다. vault 가 모르는 ID 를
/// `usage` 오류 한 줄로 돌려주기 때문에 아무도 몰랐다 — 손으로 대조해서야 드러났다.
///
/// `ReachWatchDoctorProvider` 와 같은 결로 **설치된 CLI 를 소비만** 한다(Core 미링크).
/// 판정은 agent-vault 가 소유한다 — 여기서 다시 맞히지 않는다.
public struct VaultConsumerProvider: DoctorProvider {
    public let id = "vault-consumers"

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
        self.resolveOnPath = resolveOnPath ?? VaultConsumerProvider.defaultResolve
        self.runCLI = runCLI ?? VaultConsumerProvider.defaultRunCLI
        self.pullExternalReports = pullExternalReports
    }

    public func run() async -> [DoctorFinding] {
        guard pullExternalReports else { return [] }
        // agent-vault 가 없으면 이 축은 조용히 생략한다 — vault 를 안 쓰는 기계도 있다.
        guard resolveOnPath("agent-vault", pathRoots) != nil else { return [] }
        let (code, stdout) = runCLI("agent-vault", ["consumers", "--json"], 30)
        return VaultConsumerReportMapper.map(stdout: stdout, exitCode: code, source: id)
    }

    private static func defaultResolve(cli: String, roots: [String]) -> String? {
        for root in roots {
            let p = (root as NSString).appendingPathComponent(cli)
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        let (code, out) = defaultRunCLI("/usr/bin/which", [cli], 5)
        guard code == 0 else { return nil }
        let p = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return p.isEmpty ? nil : p
    }

    private static func defaultRunCLI(
        _ cli: String, _ args: [String], _ timeout: TimeInterval
    ) -> (exit: Int32, stdout: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cli.hasPrefix("/") ? cli : "/usr/bin/env")
        process.arguments = cli.hasPrefix("/") ? args : [cli] + args
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        // stdin 을 안 주면 자식이 읽다 블록될 수 있다(codex 실측 사고와 같은 결).
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return (127, "") }
        let item = DispatchWorkItem { process.terminate() }
        DispatchQueue(label: "doctorkit.vault-consumer.timeout").asyncAfter(deadline: .now() + timeout, execute: item)
        // 파이프를 걸어두고 대기 전에 드레인하지 않으면 64KB 에서 교착한다.
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        item.cancel()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}

/// `agent-vault consumers --json` → doctor finding.
///
/// 앱당 finding 을 쏟지 않는다 — 요약 1건 + 손댈 항목만. 수백 건이 되면 doctor 가
/// 잠기고, 잠긴 doctor 는 아무도 안 본다.
public enum VaultConsumerReportMapper {
    public static func map(stdout: String, exitCode: Int32, source: String) -> [DoctorFinding] {
        // 구버전 agent-vault 는 `consumers` 를 모른다 — usage 오류(64)다.
        // 이걸 파싱 실패로 올리면 함대 절반에서 거짓 경보가 난다. 할 일을 알려준다.
        if exitCode == 64 {
            return [DoctorFinding(
                category: .credentialReach,
                severity: .info,
                body: .init(
                    subject: "agent-vault",
                    title: "설치된 agent-vault 가 자격 도달 점검을 아직 모른다",
                    detail: "consumers 명령이 없다(usage 오류). 이 축은 이번 스캔에서 생략됐다.",
                    remedy: "app-build-manager ship agent-vault-swift release"
                ),
                source: source
            )]
        }
        guard let data = stdout.data(using: .utf8),
              let root = ProbeJSON.object(from: data)
        else {
            // exit 1 은 "손댈 게 있다" 는 정상 신호다. 파싱이 안 될 때만 알린다.
            return [DoctorFinding(
                category: .credentialReach,
                severity: .warn,
                body: .init(
                    subject: "agent-vault",
                    title: "자격 도달 점검 결과를 읽을 수 없다",
                    detail: "consumers --json 출력이 JSON 이 아니다 (exit \(exitCode)).",
                    remedy: "agent-vault consumers --json 을 직접 실행해 확인"
                ),
                source: source
            )]
        }
        let result = (root["result"] as? [String: Any]) ?? root
        let rows = result["rows"] as? [[String: Any]] ?? []
        let installed = result["installedApps"] as? Int ?? 0
        let declared = result["declaredConsumers"] as? Int ?? 0

        let unregistered = rows.filter { ($0["state"] as? String) == "unregistered" }
        let orphaned = rows.filter { ($0["state"] as? String) == "orphanedRegistration" }

        var findings: [DoctorFinding] = []

        if !unregistered.isEmpty {
            let names = unregistered.compactMap { $0["key"] as? String }.sorted()
            findings.append(DoctorFinding(
                category: .credentialReach,
                severity: .fail,
                body: .init(
                    subject: "agent-vault",
                    title: "자격을 쓰는 앱 \(names.count)개가 vault 에 등록돼 있지 않다",
                    detail: "\(names.joined(separator: ", ")) — 자격 조회가 usage 오류로 죽는다.",
                    remedy: "agent-vault consumers 로 칠 명령을 확인하거나 Agent Vault 「에이전트」 화면에서 등록"
                ),
                source: source,
                payload: ["apps": names.joined(separator: ",")]
            ))
        }

        if !orphaned.isEmpty {
            let names = orphaned.compactMap { $0["key"] as? String }.sorted()
            findings.append(DoctorFinding(
                category: .credentialReach,
                severity: .warn,
                body: .init(
                    subject: "agent-vault",
                    title: "유령 등록 \(names.count)건 — 실행 파일이 없다",
                    detail: names.joined(separator: ", "),
                    remedy: "경로를 고치거나(agent set --path) 등록을 비활성화"
                ),
                source: source,
                payload: ["agents": names.joined(separator: ",")]
            ))
        }

        let dangling = rows.filter { ($0["state"] as? String) == "danglingBinding" }
        if !dangling.isEmpty {
            let names = dangling.compactMap { $0["key"] as? String }.sorted()
            findings.append(DoctorFinding(
                category: .credentialReach,
                severity: .warn,
                body: .init(
                    subject: "agent-vault",
                    title: "바인딩이 가리키는 소비자가 없다 (\(names.count)건)",
                    detail: "\(names.joined(separator: ", ")) — 그 자격은 아무도 못 쓴다.",
                    remedy: "에이전트를 등록하거나(agent add) 바인딩을 지운다(dependency remove)"
                ),
                source: source,
                payload: ["consumers": names.joined(separator: ",")]
            ))
        }

        // 두 원장이 어긋난다 — vault 는 아는데 앱이 선언을 안 했다.
        // 이걸 안 보면 "선언한 것만" 검사하는 축이 스스로의 사각을 못 좁힌다.
        let undeclared = rows.filter { ($0["state"] as? String) == "undeclaredConsumer" }
        if !undeclared.isEmpty {
            let names = undeclared.compactMap { $0["key"] as? String }.sorted()
            findings.append(DoctorFinding(
                category: .credentialReach,
                severity: .info,
                body: .init(
                    subject: "함대",
                    title: "vault 는 소비자로 아는데 앱이 선언하지 않았다 (\(names.count)개)",
                    detail: names.joined(separator: ", "),
                    remedy: "해당 앱 capabilities 의 depends 에 kind=credential 선언"
                ),
                source: source,
                payload: ["apps": names.joined(separator: ",")]
            ))
        }

        // **사각을 숨기지 않는다.** 선언한 앱만 검사하므로, 통과했다고 안심시키면 거짓이다.
        let undeclaredCount = max(0, installed - declared)
        if undeclaredCount > 0 {
            findings.append(DoctorFinding(
                category: .credentialReach,
                severity: .info,
                body: .init(
                    subject: "함대",
                    title: "자격 의존을 선언한 앱 \(declared)/\(installed)",
                    detail: "나머지 \(undeclaredCount)개는 이 점검에 안 잡힌다 — 자격을 써도 드러나지 않는다.",
                    remedy: "각 앱 capabilities 의 depends 에 kind=credential 선언"
                ),
                source: source,
                payload: ["declared": "\(declared)", "installed": "\(installed)"]
            ))
        }

        if findings.isEmpty {
            findings.append(DoctorFinding(
                category: .credentialReach,
                severity: .ok,
                body: .init(
                    subject: "agent-vault",
                    title: "자격 도달 문제 없음",
                    detail: "선언한 소비자 \(declared)개 전부 등록됨 · 유령 등록 없음."
                ),
                source: source
            ))
        }
        return findings
    }
}
