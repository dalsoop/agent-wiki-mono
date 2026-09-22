import XCTest
@testable import DoctorKit
import InstallHealthKit
import InteropKit

final class DoctorKitTests: XCTestCase {

    func testSeverityOrder() {
        XCTAssertTrue(DoctorSeverity.ok < .warn)
        XCTAssertTrue(DoctorSeverity.warn < .fail)
        XCTAssertTrue(DoctorSeverity.fail >= .warn)
    }

    func testDependencyProviderMissingBinary() async {
        let catalog = DependencyCatalog(apps: [
            AppDependencySpec(
                id: "demo",
                displayName: "Demo",
                needs: [DependencyNeed(kind: .binary, value: "definitely-not-installed-xyz")]
            ),
        ])
        let p = DependencyDoctorProvider(
            catalog: catalog,
            isExecutable: { _ in false },
            fileExists: { _ in false }
        )
        let findings = await p.run()
        XCTAssertEqual(findings.count, 1)
        XCTAssertEqual(findings[0].severity, .fail)
        XCTAssertEqual(findings[0].category, .dependency)
    }

    func testDependencyOptionalIsInfo() async {
        let catalog = DependencyCatalog(apps: [
            AppDependencySpec(
                id: "demo",
                displayName: "Demo",
                needs: [DependencyNeed(kind: .path, value: "/no/such", optional: true)]
            ),
        ])
        let p = DependencyDoctorProvider(
            catalog: catalog,
            isExecutable: { _ in false },
            fileExists: { _ in false }
        )
        let findings = await p.run()
        XCTAssertEqual(findings[0].severity, .info)
    }

    func testCatalogMergeOverlayWins() {
        let base = DependencyCatalog(apps: [
            AppDependencySpec(id: "a", displayName: "A", needs: []),
        ])
        let overlay = DependencyCatalog(apps: [
            AppDependencySpec(id: "a", displayName: "A2", needs: [
                DependencyNeed(kind: .env, value: "HOME"),
            ]),
            AppDependencySpec(id: "b", displayName: "B"),
        ])
        let m = base.merging(overlay: overlay)
        XCTAssertEqual(m.apps.count, 2)
        XCTAssertEqual(m.apps.first { $0.id == "a" }?.displayName, "A2")
        XCTAssertEqual(m.apps.first { $0.id == "a" }?.needs.count, 1)
    }

    func testExtraCopyProvider() async {
        let p = ExtraCopyDoctorProvider(
            bundleNames: ["Mounter"],
            listCandidates: { _ in
                [
                    "/Applications/Mounter.app",
                    "/Users/x/Applications/icons/Mounter.app",
                ]
            }
        )
        let f = await p.run()
        XCTAssertEqual(f.filter { $0.severity == .warn }.count, 1)
        XCTAssertTrue(f[0].detail.contains("icons"))
    }

    func testCrashProviderEmptyOk() async {
        let p = CrashReportDoctorProvider(
            reportsDir: "/tmp/no-such-diag-\(UUID().uuidString)",
            listFiles: { _ in [] }
        )
        let f = await p.run()
        XCTAssertEqual(f.count, 1)
        XCTAssertEqual(f[0].severity, .ok)
    }

    // MARK: - CrashReport 그룹화 (같은 앱 반복 → 1 finding)

    func testCrashAppNameExtractsFromDatedIps() {
        XCTAssertEqual(
            CrashReportDoctorProvider.appName(from: "app-health-guard-2026-08-09-161147.ips"),
            "app-health-guard"
        )
        XCTAssertEqual(
            CrashReportDoctorProvider.appName(from: "AgentBrowser-2026-08-07-221343.ips"),
            "AgentBrowser"
        )
    }

    func testCrashAppNameFallsBackWhenNoDatePattern() {
        // 구형 .crash 나 날짜 없는 파일 — 확장자만 뗀다.
        XCTAssertEqual(
            CrashReportDoctorProvider.appName(from: "Mounter.crash"),
            "Mounter"
        )
    }

    func testCrashProviderGroupsRepeatedCrashesIntoOne() async {
        // 같은 앱(app-health-guard)의 20회 반복 → 1 finding (count=20), 최근이면 fail.
        let recent = Date()
        let names = (0..<20).map { i in
            String(format: "app-health-guard-2026-08-09-1600%02d.ips", i)
        }
        let p = CrashReportDoctorProvider(
            now: { recent },
            listFiles: { _ in names },
            fileMtime: { _ in recent },
        )
        let f = await p.run()
        XCTAssertEqual(f.count, 1, "같은 앱 20회 → 1 finding 이어야 한다")
        XCTAssertEqual(f[0].severity, .fail)
        XCTAssertEqual(f[0].payload["active"], "true")
        XCTAssertEqual(f[0].subject, "app-health-guard")
        XCTAssertEqual(f[0].payload["count"], "20")
        XCTAssertTrue(f[0].title.contains("×20"))
    }

    func testCrashProviderDemotesOldReportsToWarn() async {
        // 24시간+ 지난 크래시는 과거 기록 → warn (현재 정상일 가능성).
        let now = Date()
        let old = now.addingTimeInterval(-60 * 60 * 48) // 48시간 전
        let p = CrashReportDoctorProvider(
            now: { now },
            listFiles: { _ in ["AgentBrowser-2026-08-07-221343.ips"] },
            fileMtime: { _ in old },
        )
        let f = await p.run()
        XCTAssertEqual(f.count, 1)
        XCTAssertEqual(f[0].severity, .warn, "24h+ 지난 크래시는 warn")
        XCTAssertEqual(f[0].payload["active"], "false")
        XCTAssertTrue(f[0].title.contains("과거 기록"))
    }

    func testCrashProviderSeparatesDifferentApps() async {
        let recent = Date()
        let p = CrashReportDoctorProvider(
            now: { recent },
            listFiles: { _ in [
                "AgentBrowser-2026-08-07-221343.ips",
                "AgentBrowser-2026-08-07-221346.ips",
                "AppBuildManager-2026-08-08-100000.ips",
            ] },
            fileMtime: { _ in recent },
        )
        let f = await p.run()
        XCTAssertEqual(f.count, 2, "AgentBrowser(2) + ADM(1) = 2 finding")
        let browser = f.first { $0.subject == "AgentBrowser" }
        XCTAssertEqual(browser?.payload["count"], "2")
    }

    func testCrashProviderSkipsOldReports() async {
        let now = Date()
        let old = now.addingTimeInterval(-60 * 60 * 24 * 30) // 30일 전 (기본 maxAge 14일 초과)
        let p = CrashReportDoctorProvider(
            now: { now },
            listFiles: { _ in ["AgentBrowser-2026-07-01-120000.ips"] },
            fileMtime: { _ in old },
        )
        let f = await p.run()
        XCTAssertEqual(f.count, 1)
        XCTAssertEqual(f[0].severity, .ok, "오래된 리포트는 무시 → ok")
    }

    func testInstallHealthBridge() {
        let issue = HealthIssue(
            kind: .duplicateBundleID,
            severity: .warning,
            subject: "net.ranode.mounter",
            detail: "two apps",
            remedy: "retire extra",
            isAutoFixable: false
        )
        let f = InstallHealthBridge.finding(from: issue)
        XCTAssertEqual(f.severity, .warn)
        XCTAssertEqual(f.category, .install)
    }

    func testManagementCatalogHasCoreOwners() throws {
        let ids = Set(ManagementAppCatalog.builtIn.map(\.id))
        for need in [
            "path-cli-health", "agent-cli-manager", "agent-host-doctor",
            "app-fleet-doctor", "app-build-manager", "agent-app-registry",
            "gujo-store-ops", "gujo-download-pipeline-auditor",
            "gujo-cloud-apps", "sparkle-update-studio", "app-notary-manager",
            "agent-surface-reach", "agent-cli-scaffold",
        ] {
            XCTAssertTrue(ids.contains(need), "missing management owner \(need)")
        }
        // SSOT export
        let data = try XCTUnwrap(try? ManagementAppCatalog.exportJSON())
        let s = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(s.contains("ManagementAppCatalog"))
        XCTAssertTrue(s.contains("path-cli-health"))
        XCTAssertTrue(s.contains("gujo-cloud-apps"))
        XCTAssertTrue(s.contains("sparkle-update-studio"))
    }

    func testSparklePendingAndFleetMappers() {
        let pending = SparklePendingMapper.map(
            stdout: #"{"ok":true,"result":{"counts":{"ahead":2,"behind":0}}}"#,
            source: "test"
        )
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending[0].payload["kind"], "ahead")
        let even = SparklePendingMapper.map(
            stdout: #"{"result":{"counts":{"ahead":0,"behind":0}}}"#,
            source: "test"
        )
        XCTAssertEqual(even[0].payload["kind"], "pending_ok")
        let fleet = SparkleFleetMapper.map(
            stdout: #"{"result":{"counts":{"feed_without_framework":70,"no_channel":4}}}"#,
            source: "test"
        )
        XCTAssertEqual(fleet.map { $0.payload["kind"] }, ["feed_without_framework", "no_channel"])
    }

    func testPathGapMapperSkipsNonHelpersAndFlagsHelpersGap() {
        // argv / dual 없음 은 오탐 — dual 없는 row 는 스킵되고 ok 요약만
        let jsonLegacy = """
        [{"canonicalCLI":"android-app-store","app":"AndroidAppStore.app","path":"/tmp/no-such.app","pathCLIPresent":false}]
        """
        let legacy = AgentCLIPathGapMapper.map(stdout: jsonLegacy, exitCode: 2, source: "test")
        XCTAssertEqual(legacy.count, 1)
        XCTAssertEqual(legacy[0].payload["kind"], "path_gap_ok")

        let jsonHelpers = """
        [{"canonicalCLI":"mac-remote-desktop","app":"MacRemoteDesktop.app","pathCLIPresent":false,"dual_entry":"helpers"}]
        """
        let f = AgentCLIPathGapMapper.map(stdout: jsonHelpers, exitCode: 2, source: "test")
        XCTAssertEqual(f.count, 1)
        XCTAssertEqual(f[0].subject, "mac-remote-desktop")
        XCTAssertEqual(f[0].payload["kind"], "path_gap")
    }

    func testHelpersContractFindsMissingProduct() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("helpers-contract-\(UUID().uuidString)")
        let app = tmp.appendingPathComponent("BrokenHelpers.app")
        let res = app.appendingPathComponent("Contents/Resources")
        try FileManager.default.createDirectory(at: res, withIntermediateDirectories: true)
        let identity: [String: String] = [
            "cli": "broken-helpers-cli",
            "dual_entry": "helpers",
        ]
        let data = try JSONSerialization.data(withJSONObject: identity)
        try data.write(to: res.appendingPathComponent("package-identity.json"))
        defer { try? FileManager.default.removeItem(at: tmp) }

        let p = ManagementAppsDoctorProvider(
            apps: [],
            applicationsDirectory: tmp.path,
            pullExternalReports: false
        )
        let findings = p.helpersContractFindings()
        XCTAssertTrue(findings.contains { $0.payload["kind"] == "helpers_product_missing" })
        XCTAssertTrue(findings.contains { $0.subject == "broken-helpers-cli" })
    }

    /// emufleet 패턴: PATH 표기 `cli` ≠ Helpers 바이너리 `cli_product`.
    /// doctor 는 product 경로로 존재 판정해야 오탐 fail 을 내지 않는다.
    func testHelpersContractAcceptsCliProductAlias() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("helpers-cli-product-\(UUID().uuidString)")
        let app = tmp.appendingPathComponent("KubernetesEmulatorFleetController.app")
        let res = app.appendingPathComponent("Contents/Resources")
        let helpers = app.appendingPathComponent("Contents/Helpers")
        try FileManager.default.createDirectory(at: res, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: helpers, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: helpers.appendingPathComponent("kubernetes-emulator-fleet-controller").path,
            contents: Data("#stub\n".utf8)
        )
        let identity: [String: Any] = [
            "cli": "emufleet",
            "program": "emufleet",
            "cli_product": "kubernetes-emulator-fleet-controller",
            "cli_helper_path": "Contents/Helpers/kubernetes-emulator-fleet-controller",
            "dual_entry": "helpers",
            "cli_aliases": ["emufleet", "k8s-emulator-set-controller"],
        ]
        let data = try JSONSerialization.data(withJSONObject: identity)
        try data.write(to: res.appendingPathComponent("package-identity.json"))
        defer { try? FileManager.default.removeItem(at: tmp) }

        let p = ManagementAppsDoctorProvider(
            apps: [],
            applicationsDirectory: tmp.path,
            pullExternalReports: false
        )
        let findings = p.helpersContractFindings()
        XCTAssertFalse(
            findings.contains { $0.payload["kind"] == "helpers_product_missing" },
            "cli_product 가 Helpers 에 있으면 missing 이면 안 됨: \(findings.map(\.title))"
        )
        XCTAssertEqual(
            ManagementAppsDoctorProvider.helpersProductName(from: identity),
            "kubernetes-emulator-fleet-controller"
        )
    }

    func testManagementInventoryFlagsPlainCopyAndMissingApp() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("mgmt-inventory-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let apps = [
            ManagementAppSpec(
                id: "agent-cli-manager",
                cli: "agent-cli-manager",
                displayName: "Agent CLI Manager",
                role: "CLI catalog",
                appBundleNames: ["Agent CLI Manager"],
                critical: true,
                expectsHelpersSymlink: true
            ),
        ]
        let p = ManagementAppsDoctorProvider(
            apps: apps,
            pathRoots: [HostPlatform.homebrewBin],
            applicationsDirectory: tmp.path,
            hooks: .init(
                resolveOnPath: { cli, _ in HostPlatform.cliBinPath(cli) },
                isSymlink: { _ in false },
                readlink: { _ in nil },
                appInstalled: { _, _ in false },
                runCLI: { _, _, _ in (0, "") }
            ),
            pullExternalReports: false
        )
        let findings = await p.run()
        XCTAssertTrue(findings.contains { $0.payload["kind"] == "plain_copy" })
        XCTAssertTrue(findings.contains { $0.payload["kind"] == "missing_app" })
        XCTAssertTrue(findings.allSatisfy { $0.category == .management })
        XCTAssertTrue(findings.contains { $0.severity == .fail })
    }

    /// 실측(2026-08-09): 기본 applicationsDirectory("/Applications")를 그대로 쓰면
    /// helpersContractFindings 가 이 호스트에 실제 설치된 다른 앱들의 package-identity.json
    /// 까지 스캔해 findings.count 가 호스트마다 달라진다(실측 22 vs 기대 1).
    /// 이 provider 의 카탈로그 인벤토리는 mock 으로 격리했지만 helpers 계약 스캔은
    /// applicationsDirectory 를 직접 FileManager 로 읽으므로, 이 값도 반드시
    /// 빈 임시 디렉터리로 주입해야 테스트가 호스트 상태에서 독립적이다.
    func testManagementInventoryOkHelpersSymlink() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("mgmt-inventory-ok-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let apps = [
            ManagementAppSpec(
                id: "path-cli-health",
                cli: "path-cli-health",
                displayName: "Path CLI Health",
                role: "PATH health",
                appBundleNames: ["PathCLIHealth"]
            ),
        ]
        let target = "/Applications/PathCLIHealth.app/Contents/Helpers/path-cli-health"
        let p = ManagementAppsDoctorProvider(
            apps: apps,
            applicationsDirectory: tmp.path,
            hooks: .init(
                resolveOnPath: { _, _ in HostPlatform.cliBinPath("path-cli-health") },
                isSymlink: { _ in true },
                readlink: { _ in target },
                appInstalled: { _, _ in true },
                runCLI: { _, _, _ in (0, "") }
            ),
            pullExternalReports: false
        )
        let findings = await p.run()
        XCTAssertEqual(findings.count, 1)
        XCTAssertEqual(findings[0].severity, .ok)
        XCTAssertEqual(findings[0].payload["kind"], "ok")
    }

    func testPathCLIHealthMapperMapsStaleCopy() {
        let path = HostPlatform.cliBinPath("gujo-store-ops")
        let json = """
        {"bad":1,"count":2,"hits":[
          {"kind":"ok","name":"a","message":"fine"},
          {"kind":"stale_copy","name":"gujo-store-ops","message":"PATH 사본","path":"\(path)","remedy":"repair"}
        ]}
        """
        let f = PathCLIHealthReportMapper.map(stdout: json, source: "test")
        XCTAssertEqual(f.count, 1)
        XCTAssertEqual(f[0].subject, "gujo-store-ops")
        XCTAssertEqual(f[0].severity, .fail)
        XCTAssertEqual(f[0].category, .management)
    }

    func testOrchestratorSortsBySeverity() async {
        struct Stub: DoctorProvider {
            let id: String
            let findings: [DoctorFinding]
            func run() async -> [DoctorFinding] { findings }
        }
        let orch = DoctorOrchestrator(providers: [
            Stub(id: "a", findings: [
                DoctorFinding(category: .other, severity: .ok, body: .init(subject: "z", title: "ok", detail: ""), source: "a"),
                DoctorFinding(category: .other, severity: .fail, body: .init(subject: "a", title: "fail", detail: ""), source: "a"),
            ]),
        ])
        let report = await orch.scan()
        XCTAssertEqual(report.findings.first?.severity, .fail)
    }

    func testEventQueueRoundTrip() throws {
        let path = NSTemporaryDirectory() + "doctor-events-\(UUID().uuidString).jsonl"
        defer { try? FileManager.default.removeItem(atPath: path) }
        let q = DoctorEventQueue(path: path, minSeverity: .warn)
        let report = DoctorReport(findings: [
            DoctorFinding(category: .crash, severity: .fail, body: .init(subject: "x", title: "c", detail: "d"), source: "t"),
            DoctorFinding(category: .other, severity: .ok, body: .init(subject: "y", title: "ok", detail: ""), source: "t"),
        ])
        try q.append(from: report)
        let all = try q.readAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].severity, .fail)
    }

    // MARK: - ReachWatch doctor 부착 (도달 갭 → fleet 요약)

    func testReachCategoryExists() {
        // .reach 케이스가 있고 allCases 에 잡힌다(GUI 가 ForEach(allCases) 로 자동 반영).
    }

    func testReachWatchCategoryExists() {
        XCTAssertEqual(DoctorCategory.reach.rawValue, "reach")
        XCTAssertTrue(DoctorCategory.allCases.contains(.reach))
    }

    func testReachWatchMapperSummarizesGapsAsFailWhenUnreached() {
        // beta=미도달(0), gamma=부분(agentSurface 만 빠짐), alpha=도달. fleetSize 3.
        let json = """
        {"ok":true,"result":{"generatedAt":"2026-08-09T00:00:00Z","fleetSize":3,
          "distribution":{"reached":1,"partial":1,"unreached":1,"averageScore":0.58},
          "apps":[
            {"app":"alpha","metFactors":["registered","capabilities","agentSurface","stateMirror"],"missingFactors":[],"score":1.0,"grade":"reached"},
            {"app":"beta","metFactors":[],
             "missingFactors":["registered","capabilities","agentSurface","stateMirror"],"score":0.0,"grade":"unreached"},
            {"app":"gamma","metFactors":["registered","capabilities","stateMirror"],"missingFactors":["agentSurface"],"score":0.75,"grade":"partial"}
          ]}}
        """
        let f = ReachWatchReportMapper.map(stdout: json, exitCode: 0, source: "reach-watch")
        XCTAssertEqual(f.count, 1)
        XCTAssertEqual(f[0].category, .reach)
        XCTAssertEqual(f[0].severity, .fail) // unreached 1 → fail
        XCTAssertEqual(f[0].subject, "reach")
        XCTAssertEqual(f[0].payload["fleetSize"], "3")
        XCTAssertEqual(f[0].payload["reached"], "1")
        XCTAssertEqual(f[0].payload["partial"], "1")
        XCTAssertEqual(f[0].payload["unreached"], "1")
        // beta(4) + gamma(1) → agentSurface 만 2회로 유일 최다.
        XCTAssertEqual(f[0].payload["dominantGap"], "agentSurface (2앱)")
        XCTAssertTrue(f[0].title.contains("2/3"))
    }

    func testReachWatchMapperOkWhenAllReached() {
        let json = """
        {"ok":true,"result":{"fleetSize":2,"apps":[
          {"app":"a","metFactors":["registered","capabilities","agentSurface","stateMirror"],"missingFactors":[],"score":1.0,"grade":"reached"},
          {"app":"b","metFactors":["registered","capabilities","agentSurface","stateMirror"],"missingFactors":[],"score":1.0,"grade":"reached"}
        ]}}
        """
        let f = ReachWatchReportMapper.map(stdout: json, exitCode: 0, source: "reach-watch")
        XCTAssertEqual(f.count, 1)
        XCTAssertEqual(f[0].severity, DoctorSeverity.ok)
        XCTAssertEqual(f[0].category, DoctorCategory.reach)
    }

    func testReachWatchMapperPartialOnlyIsWarn() {
        // 미도달 0, 부분만 → warn(fail 아님).
        let json = """
        {"ok":true,"result":{"fleetSize":1,"apps":[
          {"app":"a","metFactors":["registered"],"missingFactors":["capabilities","agentSurface","stateMirror"],"score":0.25,"grade":"partial"}
        ]}}
        """
        let f = ReachWatchReportMapper.map(stdout: json, exitCode: 0, source: "reach-watch")
        XCTAssertEqual(f.count, 1)
        XCTAssertEqual(f[0].severity, DoctorSeverity.warn)
    }

    func testReachWatchMapperEmptyOnBadEnvelope() {
        // ok:false → 도구 자체 실패, 조용히 생략.
        let f = ReachWatchReportMapper.map(
            stdout: #"{"ok":false,"error":{"message":"no repo"}}"#, exitCode: 0, source: "reach-watch")
        XCTAssertTrue(f.isEmpty)
    }

    func testReachWatchMapperEmptyOnGarbage() {
        XCTAssertTrue(ReachWatchReportMapper.map(stdout: "not json", exitCode: 0, source: "x").isEmpty)
    }

    func testReachWatchProviderSkipsWhenNotOnPath() async {
        let p = ReachWatchDoctorProvider(
            resolveOnPath: { _, _ in nil },
            runCLI: { _, _, _ in (0, "{\"ok\":true,\"result\":{\"apps\":[]}}") }
        )
        let f = await p.run()
        XCTAssertTrue(f.isEmpty) // reach-watch 없으면 당기지 않음
    }

    func testReachWatchProviderPullsScanViaRunCLI() async {
        let p = ReachWatchDoctorProvider(
            resolveOnPath: { cli, _ in
                cli == "agent-reach-watch" ? HostPlatform.cliBinPath("agent-reach-watch") : nil
            },
            runCLI: { exe, args, _ in
                XCTAssertEqual(exe, "agent-reach-watch")
                XCTAssertEqual(args, ["scan", "--json"])
                let json = """
                {"ok":true,"result":{"fleetSize":1,"apps":[{"app":"x","metFactors":[],
                 "missingFactors":["registered"],"score":0,"grade":"unreached"}]}}
                """
                return (0, json)
            }
        )
        let f = await p.run()
        XCTAssertEqual(f.count, 1)
        XCTAssertEqual(f[0].severity, .fail)
        XCTAssertEqual(f[0].source, "reach-watch")
    }

    // MARK: - StaleSource doctor 부착 (설치본 신선도 → fleet 요약)

    func testStaleSourceCategoryExists() {
        XCTAssertEqual(DoctorCategory.staleSource.rawValue, "staleSource")
        XCTAssertTrue(DoctorCategory.allCases.contains(.staleSource))
    }

    func testStaleSourceMapperEmptyArrayIsOk() {
        let f = StaleSourceReportMapper.map(stdout: "[]", exitCode: 0, source: "stale-source")
        XCTAssertEqual(f.count, 1)
        XCTAssertEqual(f[0].severity, .ok)
        XCTAssertEqual(f[0].category, .staleSource)
    }

    func testStaleSourceMapperSummarizesHitsAsWarn() {
        // path-cli-health stale-source --json 은 봉투 없는 맨 배열.
        let browserPath = HostPlatform.cliBinPath("agent-browser")
        let gujoPath = HostPlatform.cliBinPath("gujo")
        let json = """
        [
          {"kind":"stale_source","name":"agent-browser","path":"\(browserPath)",
           "message":"설치본이 origin/main 뒤처짐","remedy":"app-build-manager ship apps/agent-browser-swift release"},
          {"kind":"stale_source","name":"gujo","path":"\(gujoPath)",
           "message":"설치본이 origin/main 뒤처짐","remedy":"app-build-manager ship apps/gujo-swift release"}
        ]
        """
        let f = StaleSourceReportMapper.map(stdout: json, exitCode: 1, source: "stale-source")
        XCTAssertEqual(f.count, 1)
        XCTAssertEqual(f[0].severity, .warn)
        XCTAssertEqual(f[0].subject, "stale-source")
        XCTAssertEqual(f[0].payload["count"], "2")
        XCTAssertEqual(f[0].payload["apps"], "agent-browser,gujo")
        XCTAssertTrue(f[0].title.contains("2"))
    }

    func testStaleSourceMapperEmptyOnExecFailure() {
        // exit 127 = path-cli-health 실행 자체 실패 — 조용히 생략(설치 안 됐다는 뜻과 구분 안 됨).
        XCTAssertTrue(StaleSourceReportMapper.map(stdout: "", exitCode: 127, source: "x").isEmpty)
    }

    func testStaleSourceMapperEmptyOnGarbage() {
        XCTAssertTrue(StaleSourceReportMapper.map(stdout: "not json", exitCode: 0, source: "x").isEmpty)
    }

    func testStaleSourceProviderSkipsWhenNotOnPath() async {
        let p = StaleSourceDoctorProvider(
            resolveOnPath: { _, _ in nil },
            runCLI: { _, _, _ in (0, "[]") }
        )
        let f = await p.run()
        XCTAssertTrue(f.isEmpty) // path-cli-health 없으면 당기지 않음
    }

    func testStaleSourceProviderPullsScanViaRunCLI() async {
        let xPath = HostPlatform.cliBinPath("x")
        let p = StaleSourceDoctorProvider(
            resolveOnPath: { cli, _ in
                cli == "path-cli-health" ? HostPlatform.cliBinPath("path-cli-health") : nil
            },
            runCLI: { exe, args, _ in
                XCTAssertEqual(exe, "path-cli-health")
                XCTAssertEqual(args, ["stale-source", "--json"])
                return (1, #"[{"kind":"stale_source","name":"x","path":"\#(xPath)","message":"m"}]"#)
            }
        )
        let f = await p.run()
        XCTAssertEqual(f.count, 1)
        XCTAssertEqual(f[0].severity, DoctorSeverity.warn)
        XCTAssertEqual(f[0].source, "stale-source")
    }

    func testManagementAppsProviderDefaultRunCLILargeOutputDoesNotDeadlock() {
        let (exitCode, stdout) = ManagementAppsDoctorProvider.defaultRunCLI(
            "/bin/sh",
            ["-c", "python3 -c 'print(\"M\" * 100000)'"],
            10
        )
        XCTAssertEqual(exitCode, 0)
        XCTAssertGreaterThanOrEqual(stdout.count, 100000)
    }

    func testStaleSourceProviderDefaultRunCLILargeOutputDoesNotDeadlock() {
        let (exitCode, stdout) = StaleSourceDoctorProvider.defaultRunCLI(
            "/bin/sh",
            ["-c", "python3 -c 'print(\"S\" * 100000)'"],
            10
        )
        XCTAssertEqual(exitCode, 0)
        XCTAssertGreaterThanOrEqual(stdout.count, 100000)
    }

    func testReachWatchProviderDefaultRunCLILargeOutputDoesNotDeadlock() {
        let (exitCode, stdout) = ReachWatchDoctorProvider.defaultRunCLI(
            "/bin/sh",
            ["-c", "python3 -c 'print(\"R\" * 100000)'"],
            10
        )
        XCTAssertEqual(exitCode, 0)
        XCTAssertGreaterThanOrEqual(stdout.count, 100000)
    }
}
