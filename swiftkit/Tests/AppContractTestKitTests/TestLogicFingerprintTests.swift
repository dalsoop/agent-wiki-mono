import XCTest
import AppContractTestKit

final class TestLogicFingerprintTests: XCTestCase {
    private let analyzer = TestLogicAnalyzer()

    func testCodableRoundTripFingerprint() {
        let smokeSnippet = """
        func testMirrorStateEncodes() throws {
            var state = StateMirrorAdoption.State()
            state.accountCount = 2
            state.subscriptionMonthlyByCurrency = ["KRW": 45000, "USD": 40]
            state.totalAssetsByCurrency = ["KRW": 10000000]
            state.totalLiabilitiesByCurrency = ["KRW": 2000000]
            state.netWorthByCurrency = ["KRW": 8000000]
            state.budgetExceededCount = 1
            state.upcoming = ["D-3 Claude $20.00"]
            let data = try JSONEncoder().encode(state)
            let decoded = try JSONDecoder().decode(StateMirrorAdoption.State.self, from: data)
            XCTAssertEqual(decoded.accountCount, 2)
            XCTAssertEqual(decoded.subscriptionMonthlyByCurrency["KRW"], 45000)
            XCTAssertEqual(decoded.totalAssetsByCurrency["KRW"], 10000000)
            XCTAssertEqual(decoded.totalLiabilitiesByCurrency["KRW"], 2000000)
            XCTAssertEqual(decoded.netWorthByCurrency["KRW"], 8000000)
            XCTAssertEqual(decoded.budgetExceededCount, 1)
        }
        """

        let genericSnippet = """
        func testPayloadRoundTrip() throws {
            let original = UserProfile(id: "u-101", name: "Tester", role: "admin")
            let payload = try JSONEncoder().encode(original)
            let restored = try JSONDecoder().decode(UserProfile.self, from: payload)
            XCTAssertEqual(original, restored)
        }
        """

        let plistSnippet = """
        func testConfigRoundTrip() throws {
            let config = SystemConfig(timeout: 60, retries: 3)
            let data = try PropertyListEncoder().encode(config)
            let decoded = try PropertyListDecoder().decode(SystemConfig.self, from: data)
            XCTAssertEqual(config, decoded)
        }
        """

        for snippet in [smokeSnippet, genericSnippet, plistSnippet] {
            XCTAssertEqual(analyzer.analyze(snippet), .codableRoundTrip)
            XCTAssertEqual(analyzer.contractID(for: snippet), ContractID.codableRoundTrip)
            XCTAssertEqual(analyzer.contractID(for: snippet), ContractID.codableIsomorphismV1)
            XCTAssertEqual(TestLogicAnalyzer.detectContractID(snippet), ContractID.codableRoundTrip)
        }
    }

    func testCLIHelpExitZeroFingerprint() {
        let loopHelpSnippet = """
        func testAuditSubcommandsHelpExitsZero() async {
            for sub in ["verify", "audit", "record-outcome"] {
                let long = await AuditCLI.run([sub, "--help"])
                XCTAssertEqual(long, AuditExitCode.success.rawValue, "\\(sub) --help")
                let short = await AuditCLI.run([sub, "-h"])
                XCTAssertEqual(short, AuditExitCode.success.rawValue, "\\(sub) -h")
            }
        }
        """

        let adoptHelpSnippet = """
        func testAdoptHelpExitsZero() {
            XCTAssertEqual(AdoptCLI.run(["adopt", "--help"]), AuditExitCode.success.rawValue)
            XCTAssertEqual(AdoptCLI.run(["adopt", "-h"]), AuditExitCode.success.rawValue)
            XCTAssertEqual(AdoptCLI.run(["--help"]), AuditExitCode.success.rawValue)
            XCTAssertEqual(
                AdoptCLI.run(["adopt", "--app", "x", "--help"]),
                AuditExitCode.success.rawValue
            )
        }
        """

        let usageSnippet = """
        func testUsageTextsAreNonEmptyAndContainRunnableExamples() {
            XCTAssertFalse(AuditCLI.usageText.isEmpty)
            XCTAssertFalse(AdoptCLI.usageText.isEmpty)
            XCTAssertTrue(AuditCLI.usageText.contains("예시:"))
            XCTAssertTrue(AdoptCLI.usageText.contains("예시:"))
        }
        """

        let processRunnerSnippet = """
        func testHelpFlagReturnsZero() throws {
            let result = try ProcessRunner.run(executable: "my-cli", arguments: ["--help"])
            XCTAssertEqual(result.exitCode, 0)
        }
        """

        for snippet in [loopHelpSnippet, adoptHelpSnippet, usageSnippet, processRunnerSnippet] {
            XCTAssertEqual(analyzer.analyze(snippet), .cliHelpExitZero)
            XCTAssertEqual(analyzer.contractID(for: snippet), ContractID.cliHelpExitZero)
            XCTAssertEqual(analyzer.contractID(for: snippet), ContractID.cliHelpParityV1)
            XCTAssertEqual(TestLogicAnalyzer.detectContractID(snippet), ContractID.cliHelpExitZero)
        }
    }

    func testStateMirrorEmitFingerprint() {
        let worktreeSnippet = """
        func testPublishShapeAndLiveCount() throws {
            let snapshot = LifecycleSnapshot(
                workspaceRoot: "/ws",
                featureCount: 3,
                limit: 8,
                items: []
            )
            LifecycleStateMirror.publish(snapshot)

            let url = stateDir.appendingPathComponent("worktree-lifecycle.json")
            let root = try XCTUnwrap(
                try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any]
            )
            XCTAssertEqual(root["app"] as? String, "worktree-lifecycle")

            let state = try XCTUnwrap(root["state"] as? [String: Any])
            XCTAssertEqual(state["workspaceRoot"] as? String, "/ws")
            XCTAssertEqual(state["featureCount"] as? Int, 3)
            XCTAssertEqual(state["gateOpen"] as? Bool, true)
        }
        """

        let envStateMirrorSnippet = """
        func testStateMirrorEmitsToStateDirectory() throws {
            setenv("SWIFT_APP_STATE_DIRECTORY", stateDir.path, 1)
            StatePublisher.publish(sampleRecord)
            let file = stateDir.appendingPathComponent("mirror.json")
            XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        }
        """

        for snippet in [worktreeSnippet, envStateMirrorSnippet] {
            XCTAssertEqual(analyzer.analyze(snippet), .stateMirrorEmit)
            XCTAssertEqual(analyzer.contractID(for: snippet), ContractID.stateMirrorEmit)
            XCTAssertEqual(analyzer.contractID(for: snippet), ContractID.stateMirrorSafetyV1)
            XCTAssertEqual(TestLogicAnalyzer.detectContractID(snippet), ContractID.stateMirrorEmit)
        }
    }

    func testHermeticSandboxFingerprint() {
        let tenantSnippet = """
        func testReadsAndWritesOnlyRequestedHippocampusTenant() async throws {
            let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: home) }
            let alpha = "tenant:alpha", beta = "tenant:beta"
            let alphaEngram = engram("나는 알파 기억이다.", tenant: alpha, irritation: 0.8)
            let betaEngram = engram("나는 베타 기억이다.", tenant: beta, freshness: 0.9, stability: 0.9)
            try seedHippocampus([alphaEngram], tenant: alpha, home: home)
            try seedHippocampus([betaEngram], tenant: beta, home: home)
            let service = DalDreamConsolidateService(baseDirectory: home)

            _ = try await service.runConsolidation(tenantID: alpha)
            let betaLedger = try await service.listEngrams(tenantID: beta)
            XCTAssertEqual(betaLedger.map(\\.id), [betaEngram.id])
        }
        """

        let sandboxDirectorySnippet = """
        func testSandboxIsolationCreatesUniqueDirectory() throws {
            let sandboxURL = FileManager.default.temporaryDirectory.appendingPathComponent("sandbox-\\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: sandboxURL, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: sandboxURL) }
            setenv("APP_HOME_OVERRIDE", sandboxURL.path, 1)
            defer { unsetenv("APP_HOME_OVERRIDE") }
            XCTAssertTrue(FileManager.default.fileExists(atPath: sandboxURL.path))
        }
        """

        for snippet in [tenantSnippet, sandboxDirectorySnippet] {
            XCTAssertEqual(analyzer.analyze(snippet), .hermeticSandbox)
            XCTAssertEqual(analyzer.contractID(for: snippet), ContractID.hermeticSandbox)
            XCTAssertEqual(analyzer.contractID(for: snippet), ContractID.hermeticSandboxV1)
            XCTAssertEqual(TestLogicAnalyzer.detectContractID(snippet), ContractID.hermeticSandbox)
        }
    }

    func testUnknownCustomDomainPreserved() {
        let businessCalculationSnippet = """
        func testNaggingThresholdCalculation() {
            let calc = NaggingCalculator(baseScore: 42.0)
            let overdueDays = 5
            let penalty = calc.computePenalty(for: overdueDays, priority: .high)
            XCTAssertEqual(penalty, 105.0)
            XCTAssertTrue(calc.shouldNotify(penalty: penalty))
        }
        """

        let graphAlgorithmSnippet = """
        func testTopologicalSortResolvesOrder() throws {
            var graph = DependencyGraph()
            graph.addDependency(child: "B", parent: "A")
            graph.addDependency(child: "C", parent: "B")
            let resolved = try graph.resolveExecutionOrder()
            XCTAssertEqual(resolved, ["A", "B", "C"])
        }
        """

        let domainParserSnippet = """
        func testKoreanTokenDecomposition() {
            let tokenizer = HangulTokenizer()
            let tokens = tokenizer.tokenize("한글 형태소 분석 테스트")
            XCTAssertEqual(tokens.count, 4)
            XCTAssertEqual(tokens[0].text, "한글")
        }
        """

        let contextScopeSnippet = """
        func testScopeIsPersonal() {
            XCTAssertEqual(PersonalLedgerDomain.scope, .personal)
            XCTAssertEqual(PersonalLedgerDomain.identifier, "personal-ledger")
        }
        """

        for snippet in [businessCalculationSnippet, graphAlgorithmSnippet, domainParserSnippet, contextScopeSnippet] {
            XCTAssertEqual(analyzer.analyze(snippet), .unknownCustomDomain)
            XCTAssertNil(analyzer.contractID(for: snippet))
            XCTAssertNil(TestLogicAnalyzer.detectContractID(snippet))
        }
    }

    func testContractIDMappingIntegrity() {
        XCTAssertEqual(TestPatternFingerprint.codableRoundTrip.contractID, ContractID.codableRoundTrip)
        XCTAssertEqual(TestPatternFingerprint.cliHelpExitZero.contractID, ContractID.cliHelpExitZero)
        XCTAssertEqual(TestPatternFingerprint.stateMirrorEmit.contractID, ContractID.stateMirrorEmit)
        XCTAssertEqual(TestPatternFingerprint.hermeticSandbox.contractID, ContractID.hermeticSandbox)
        XCTAssertNil(TestPatternFingerprint.unknownCustomDomain.contractID)

        XCTAssertEqual(ContractID.codableIsomorphismV1, ContractID.codableRoundTrip)
        XCTAssertEqual(ContractID.cliHelpParityV1, ContractID.cliHelpExitZero)
        XCTAssertEqual(ContractID.stateMirrorSafetyV1, ContractID.stateMirrorEmit)
        XCTAssertEqual(ContractID.hermeticSandboxV1, ContractID.hermeticSandbox)

        XCTAssertEqual(TestPatternFingerprint.allCases.count, 5)

        for contract in [ContractID.codableRoundTrip, ContractID.cliHelpExitZero, ContractID.stateMirrorEmit, ContractID.hermeticSandbox] {
            XCTAssertFalse(contract.rawValue.isEmpty)
        }
    }
}
