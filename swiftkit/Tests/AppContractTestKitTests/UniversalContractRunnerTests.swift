import XCTest
import AppContractTestKit

final class UniversalContractRunnerTests: XCTestCase {
    private func makeValidTarget() -> UniversalContractTargetDescriptor {
        let helpText = """
        Usage: virtual-pilot <command> [options]

        Commands:
          inspect   Inspect runtime parameters
          export    Export system state
          status    Print system status
        """
        let validState = Data("""
        {"initialized": true, "version": "1.0.0", "activeWorkers": 4}
        """.utf8)
        let validPayload = Data("""
        {"appId": "virtual-pilot-01", "settings": {"retryLimit": 3, "timeout": 30.0}}
        """.utf8)

        return UniversalContractTargetDescriptor(
            name: "virtual-pilot",
            cliBinaryName: "virtual-pilot",
            statePath: "/tmp/virtual-pilot/state.json",
            modelType: "VirtualPilotConfig",
            cliHelpOutput: helpText,
            cliCommands: ["inspect", "export", "status"],
            samplePayload: validPayload,
            stateData: validState,
            allowedSandboxDirectories: ["/tmp/virtual-pilot"],
            accessPaths: ["/tmp/virtual-pilot/state.json"]
        )
    }

    func testVirtualTargetAllStandardContractsPass() {
        let target = makeValidTarget()
        let runner = UniversalContractRunner()
        let contracts: [ContractID] = [
            .cliHelpParityV1,
            .stateMirrorSafetyV1,
            .codableIsomorphismV1
        ]

        let summary = runner.run(target: target, contracts: contracts)

        XCTAssertTrue(summary.isSuccess)
        XCTAssertEqual(summary.totalCount, 3)
        XCTAssertEqual(summary.passedCount, 3)
        XCTAssertEqual(summary.failedCount, 0)
        XCTAssertGreaterThanOrEqual(summary.duration, 0.0)

        for contractID in contracts {
            guard let result = summary.result(for: contractID) else {
                XCTFail("Missing result for contract \(contractID.rawValue)")
                continue
            }
            XCTAssertTrue(result.isPass)
            XCTAssertEqual(result.status, .passed)
            XCTAssertNil(result.counterExample)
            XCTAssertFalse(result.message.isEmpty)
        }
    }

    func testCliHelpParityFailureExtractsCounterExample() {
        let deficientTarget = UniversalContractTargetDescriptor(
            name: "broken-cli-app",
            cliBinaryName: "broken-cli",
            statePath: "/tmp/state.json",
            cliHelpOutput: "Usage: broken-cli inspect",
            cliCommands: ["inspect", "unadvertised-command"]
        )
        let runner = UniversalContractRunner()

        let summary = runner.run(target: deficientTarget, contracts: [.cliHelpParityV1])

        XCTAssertFalse(summary.isSuccess)
        XCTAssertEqual(summary.failedCount, 1)
        guard let result = summary.result(for: .cliHelpParityV1) else {
            XCTFail("Missing result for .cliHelpParityV1")
            return
        }
        XCTAssertFalse(result.isPass)
        XCTAssertEqual(result.status, .failed)
        guard let counterExample = result.counterExample else {
            XCTFail("Expected counter-example for cliHelpParity failure")
            return
        }
        XCTAssertTrue(counterExample.contains("unadvertised-command"))
    }

    func testStateMirrorSafetyPathTraversalFailureExtractsCounterExample() {
        let target = UniversalContractTargetDescriptor(
            name: "traversal-app",
            cliBinaryName: "traversal-app",
            statePath: "../../etc/shadow"
        )
        let runner = UniversalContractRunner()

        let summary = runner.run(target: target, contracts: [.stateMirrorSafetyV1])

        XCTAssertFalse(summary.isSuccess)
        guard let result = summary.result(for: .stateMirrorSafetyV1) else {
            XCTFail("Missing result for .stateMirrorSafetyV1")
            return
        }
        XCTAssertFalse(result.isPass)
        guard let counterExample = result.counterExample else {
            XCTFail("Expected counter-example for stateMirrorSafety failure")
            return
        }
        XCTAssertTrue(counterExample.contains("Path traversal"))
    }

    func testStateMirrorSafetyCorruptedDataFailureExtractsCounterExample() {
        let target = UniversalContractTargetDescriptor(
            name: "corrupted-state-app",
            cliBinaryName: "corrupted-state-app",
            statePath: "/tmp/valid-state.json",
            stateData: Data("<<invalid-json-content>>".utf8)
        )
        let runner = UniversalContractRunner()

        let summary = runner.run(target: target, contracts: [.stateMirrorSafetyV1])

        XCTAssertFalse(summary.isSuccess)
        guard let result = summary.result(for: .stateMirrorSafetyV1) else {
            XCTFail("Missing result for .stateMirrorSafetyV1")
            return
        }
        XCTAssertFalse(result.isPass)
        guard let counterExample = result.counterExample else {
            XCTFail("Expected counter-example for stateMirrorSafety corruption")
            return
        }
        XCTAssertTrue(counterExample.contains("JSON"))
    }

    func testCodableIsomorphismFailureExtractsCounterExample() {
        let target = UniversalContractTargetDescriptor(
            name: "broken-iso-app",
            cliBinaryName: "broken-iso",
            statePath: "/tmp/state.json",
            samplePayload: Data("{\"bad\": malformed}".utf8)
        )
        let runner = UniversalContractRunner()

        let summary = runner.run(target: target, contracts: [.codableIsomorphismV1])

        XCTAssertFalse(summary.isSuccess)
        guard let result = summary.result(for: .codableIsomorphismV1) else {
            XCTFail("Missing result for .codableIsomorphismV1")
            return
        }
        XCTAssertFalse(result.isPass)
        guard let counterExample = result.counterExample else {
            XCTFail("Expected counter-example for codableIsomorphism failure")
            return
        }
        XCTAssertTrue(counterExample.contains("payload") || counterExample.contains("parse"))
    }

    func testHermeticSandboxPassAndFailureExtractsCounterExample() {
        let runner = UniversalContractRunner()

        let passingTarget = UniversalContractTargetDescriptor(
            name: "sandboxed-app",
            cliBinaryName: "sandboxed-app",
            statePath: "/tmp/sandboxed-app/state.json",
            allowedSandboxDirectories: ["/private/tmp/sandboxed-app", "/tmp/sandboxed-app"],
            accessPaths: ["/tmp/sandboxed-app/cache.db"]
        )
        let passSummary = runner.run(target: passingTarget, contracts: [.hermeticSandboxV1])
        XCTAssertTrue(passSummary.isSuccess)

        let escapingTarget = UniversalContractTargetDescriptor(
            name: "escaping-app",
            cliBinaryName: "escaping-app",
            statePath: "/tmp/sandboxed-app/state.json",
            allowedSandboxDirectories: ["/tmp/sandboxed-app"],
            accessPaths: ["/etc/passwd"]
        )
        let failSummary = runner.run(target: escapingTarget, contracts: [.hermeticSandboxV1])
        XCTAssertFalse(failSummary.isSuccess)
        guard let failResult = failSummary.result(for: .hermeticSandboxV1) else {
            XCTFail("Missing result for .hermeticSandboxV1")
            return
        }
        XCTAssertFalse(failResult.isPass)
        guard let counterExample = failResult.counterExample else {
            XCTFail("Expected counter-example for hermetic sandbox escape")
            return
        }
        XCTAssertTrue(counterExample.contains("/etc/passwd"))
    }

    func testUnregisteredContractFailsGracefullyWithCounterExample() {
        let target = makeValidTarget()
        let runner = UniversalContractRunner()
        let unknownContract = ContractID("unknown-contract-55a0b1c2")

        let summary = runner.run(target: target, contracts: [unknownContract])

        XCTAssertFalse(summary.isSuccess)
        XCTAssertEqual(summary.failedCount, 1)
        guard let result = summary.result(for: unknownContract) else {
            XCTFail("Missing result for unknown contract")
            return
        }
        XCTAssertEqual(result.status, .failed)
        guard let counterExample = result.counterExample else {
            XCTFail("Expected counter-example for unregistered contract")
            return
        }
        XCTAssertTrue(counterExample.contains("UnregisteredContractID"))
    }

    func testCustomContractRegistrationAndAsyncRun() async {
        let registry = UniversalContractRegistry()
        let customContractID = ContractID("custom-audit-v1")

        registry.register(contractID: customContractID) { target in
            if target.name.hasPrefix("virtual-") {
                return .pass(message: "Audit passed for virtual app")
            } else {
                return .fail(
                    message: "App name prefix mismatch",
                    counterExample: "Expected prefix 'virtual-', got '\(target.name)'"
                )
            }
        }

        let runner = UniversalContractRunner(registry: registry)
        let validTarget = makeValidTarget()

        let summary = await runner.runAsync(target: validTarget, contracts: [customContractID])
        XCTAssertTrue(summary.isSuccess)
        XCTAssertEqual(summary.passedCount, 1)

        let invalidTarget = UniversalContractTargetDescriptor(
            name: "legacy-pilot",
            cliBinaryName: "legacy",
            statePath: "/tmp/legacy.json"
        )
        let failSummary = await runner.runAsync(target: invalidTarget, contracts: [customContractID])
        XCTAssertFalse(failSummary.isSuccess)
        guard let failResult = failSummary.result(for: customContractID) else {
            XCTFail("Missing result for custom contract")
            return
        }
        XCTAssertEqual(failResult.counterExample, "Expected prefix 'virtual-', got 'legacy-pilot'")
    }
}
