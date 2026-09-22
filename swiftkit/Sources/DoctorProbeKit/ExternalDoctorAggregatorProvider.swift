import DoctorContract
import Foundation
import InteropKit

/// 외부 doctor CLI 6개를 병렬 호출해 결과를 통합 스캔에 합친다.
///
/// Flutter의 `DoctorValidatorsProvider` + 마이크로서비스 watchdog 패턴.
/// 각 CLI의 `--json` 출력을 느슨하게 파싱(Core 링크 없음)하고,
/// 한 CLI가 타임아웃/크래시해도 나머지는 계속 돈다.
public struct ExternalDoctorAggregatorProvider: DoctorProvider {
    public let id = "external-doctors"

    public struct ExternalDoctor: Sendable {
        public let cli: String
        public let args: [String]
        public let category: DoctorCategory
        public let timeout: TimeInterval

        public init(cli: String, args: [String] = ["--json"], category: DoctorCategory, timeout: TimeInterval = 30) {
            self.cli = cli
            self.args = args
            self.category = category
            self.timeout = timeout
        }
    }

    private let doctors: [ExternalDoctor]
    private let pathRoots: [String]
    private let runCLI: @Sendable (String, [String], TimeInterval) -> (exit: Int32, stdout: String)

    public init(
        doctors: [ExternalDoctor]? = nil,
        pathRoots: [String] = Self.defaultPathRoots,
        runCLI: (@Sendable (String, [String], TimeInterval) -> (exit: Int32, stdout: String))? = nil
    ) {
        self.doctors = doctors ?? Self.defaultDoctors
        self.pathRoots = pathRoots
        self.runCLI = runCLI ?? Self.defaultRunCLI
    }

    public static let defaultPathRoots = [HostPlatform.homebrewBin, "/usr/local/bin"]

    public static let defaultDoctors: [ExternalDoctor] = [
        ExternalDoctor(cli: "agent-host-doctor", args: ["check", "--json"], category: .management, timeout: 30),
        ExternalDoctor(cli: "agent-worktree-doctor", args: ["status", "--json"], category: .management, timeout: 15),
        ExternalDoctor(cli: "app-health-guard", args: ["check", "--json"], category: .management, timeout: 30),
        ExternalDoctor(cli: "app-launch-doctor", args: ["list", "--json"], category: .install, timeout: 30),
        ExternalDoctor(cli: "path-cli-health", args: ["fast", "--json"], category: .install, timeout: 20),
    ]

    public func run() async -> [DoctorFinding] {
        await withTaskGroup(of: [DoctorFinding].self) { group in
            for doc in doctors {
                group.addTask { [runCLI] in
                    let resolved = Self.resolve(doc.cli, roots: pathRoots)
                    guard resolved != nil else {
                        return [DoctorFinding(
                            category: doc.category,
                            severity: .info,
                            body: .init(
                                subject: doc.cli,
                                title: "\(doc.cli) 미설치 — 이 축 생략",
                                detail: "PATH에 \(doc.cli) 없음"
                            ),
                            source: "external-doctors"
                        )]
                    }
                    let (code, stdout) = runCLI(doc.cli, doc.args, doc.timeout)
                    return Self.mapFindings(cli: doc.cli, stdout: stdout, exitCode: code, category: doc.category)
                }
            }
            var all: [DoctorFinding] = []
            for await batch in group { all.append(contentsOf: batch) }
            return all
        }
    }

    // MARK: - Mapping

    static func mapFindings(cli: String, stdout: String, exitCode: Int32, category: DoctorCategory) -> [DoctorFinding] {
        if exitCode == 127 {
            return [DoctorFinding(
                category: category,
                severity: .info,
                body: .init(
                    subject: cli,
                    title: "\(cli) 실행 실패 (exit 127)",
                    detail: "CLI를 찾을 수 없거나 실행 권한 없음"
                ),
                source: "external-doctors"
            )]
        }

        guard let data = stdout.data(using: .utf8),
              let obj = ProbeJSON.object(from: data)
        else {
            if exitCode != 0 {
                return [DoctorFinding(
                    category: category,
                    severity: .warn,
                    body: .init(
                        subject: cli,
                        title: "\(cli) 비정상 종료 (exit \(exitCode))",
                        detail: String(stdout.prefix(200))
                    ),
                    source: "external-doctors"
                )]
            }
            return []
        }

        // doctor/v1 프로토콜: "schema": "doctor/v1" 이면 findings 배열에서 직접 생성
        if let schema = obj["schema"] as? String, schema == "doctor/v1" {
            return mapDoctorV1(cli: cli, obj: obj, category: category)
        }

        // 기존 느슨한 파싱 (하위호환) + contract-violation info
        var results = mapLegacy(cli: cli, obj: obj, category: category, stdout: stdout)
        results.append(DoctorFinding(
            category: category,
            severity: .info,
            body: .init(
                subject: cli,
                title: "\(cli): doctor-contract-violation",
                detail: "출력에 \"schema\": \"doctor/v1\" 없음 — 느슨한 파싱 사용"
            ),
            source: "external-doctors"
        ))
        return results
    }

    // MARK: - doctor/v1

    private static func mapDoctorV1(cli: String, obj: [String: Any], category: DoctorCategory) -> [DoctorFinding] {
        guard let items = obj["findings"] as? [[String: Any]] else {
            return [DoctorFinding(
                category: category,
                severity: .warn,
                body: .init(
                    subject: cli,
                    title: "\(cli): doctor/v1 schema이나 findings 배열 없음",
                    detail: ""
                ),
                source: "external-doctors"
            )]
        }
        if items.isEmpty {
            return [DoctorFinding(
                category: category,
                severity: .ok,
                body: .init(
                    subject: cli,
                    title: "\(cli): 정상 (doctor/v1)",
                    detail: ""
                ),
                source: "external-doctors"
            )]
        }
        return items.map { item in
            let title = (item["title"] as? String) ?? (item["message"] as? String) ?? "이상"
            let detail = (item["detail"] as? String) ?? ""
            let sevStr = (item["severity"] as? String) ?? "warn"
            let severity: DoctorSeverity = switch sevStr {
            case "ok": .ok
            case "info": .info
            case "fail", "error": .fail
            default: .warn
            }
            let cat: DoctorCategory
            if let catStr = item["category"] as? String,
               let parsed = DoctorCategory(rawValue: catStr) {
                cat = parsed
            } else {
                cat = category
            }
            return DoctorFinding(
                category: cat,
                severity: severity,
                body: .init(
                    subject: cli,
                    title: "\(cli): \(title)",
                    detail: detail,
                    remedy: item["remedy"] as? String
                ),
                source: "external-doctors"
            )
        }
    }

    // MARK: - Legacy (pre-v1)

    private static func mapLegacy(cli: String, obj: [String: Any], category: DoctorCategory, stdout: String = "") -> [DoctorFinding] {
        let ok = (obj["ok"] as? Bool) ?? true
        let result = (obj["result"] as? [String: Any]) ?? obj

        if ok {
            let summary = (result["summary"] as? String)
                ?? (result["status"] as? String)
                ?? "정상"
            return [DoctorFinding(
                category: category,
                severity: .ok,
                body: .init(
                    subject: cli,
                    title: "\(cli): \(summary)",
                    detail: ""
                ),
                source: "external-doctors"
            )]
        }

        var findings: [DoctorFinding] = []
        if let issues = result["issues"] as? [[String: Any]] {
            for issue in issues {
                let title = (issue["title"] as? String) ?? (issue["message"] as? String) ?? "이상"
                let detail = (issue["detail"] as? String) ?? ""
                let sevStr = (issue["severity"] as? String) ?? "warn"
                let severity: DoctorSeverity = sevStr == "fail" || sevStr == "error" ? .fail : .warn
                findings.append(DoctorFinding(
                    category: category,
                    severity: severity,
                    body: .init(
                        subject: cli,
                        title: "\(cli): \(title)",
                        detail: detail,
                        remedy: issue["remedy"] as? String
                    ),
                    source: "external-doctors"
                ))
            }
        }

        if findings.isEmpty {
            let msg = (result["error"] as? String) ?? (result["message"] as? String) ?? "실패"
            findings.append(DoctorFinding(
                category: category,
                severity: .fail,
                body: .init(
                    subject: cli,
                    title: "\(cli): \(msg)",
                    detail: String(stdout.prefix(300))
                ),
                source: "external-doctors"
            ))
        }

        return findings
    }

    // MARK: - CLI execution

    static func resolve(_ cli: String, roots: [String]) -> String? {
        for root in roots {
            let p = (root as NSString).appendingPathComponent(cli)
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        return nil
    }

    private static func defaultRunCLI(
        _ exe: String,
        _ args: [String],
        _ timeout: TimeInterval
    ) -> (exit: Int32, stdout: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = [exe] + args
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
