import XCTest
@testable import GujoStoreOpsCore

final class HubServiceProbeTests: XCTestCase {
    func testDecodeServicePackJSON() throws {
        let json = """
        {
          "ok": true,
          "ready": true,
          "fetchedAt": "t",
          "gates": [
            {
              "id": "supply",
              "ok": true,
              "required": true,
              "skipped": false,
              "exitCode": 0,
              "detail": "download pipeline ready",
              "durationMs": 10
            }
          ],
          "failGate": null,
          "prescription": null
        }
        """
        let report = try JSONDecoder().decode(ServicePackCLIReport.self, from: Data(json.utf8))
        XCTAssertTrue(report.ready)
        XCTAssertEqual(report.gates.count, 1)
        XCTAssertEqual(report.gates[0].id, "supply")
    }

    func testAuditorResolve() {
        // path may or may not exist in CI
        let path = HubServiceProbe.resolveAuditor()
        if let path {
            XCTAssertTrue(path.contains("gujo-download-pipeline-auditor"))
        }
    }

    func testBinaryProbeSpecDefaults() {
        let spec = BinaryProbeSpec.gujoAuditorSpec
        XCTAssertEqual(spec.executableName, "gujo-download-pipeline-auditor")
        XCTAssertEqual(spec.minVersion, "1.0.0")
        XCTAssertEqual(spec.requiredArch, "arm64")
        XCTAssertFalse(spec.searchPaths.isEmpty)
    }

    func testCompareVersions() {
        XCTAssertEqual(FastBinaryProbeEngine.compareVersions("1.0.0", "1.0.0"), .orderedSame)
        XCTAssertEqual(FastBinaryProbeEngine.compareVersions("1.0.1", "1.0.0"), .orderedDescending)
        XCTAssertEqual(FastBinaryProbeEngine.compareVersions("1.0.0", "1.0.1"), .orderedAscending)
        XCTAssertEqual(FastBinaryProbeEngine.compareVersions("2.0.0", "1.9.9"), .orderedDescending)
        XCTAssertEqual(FastBinaryProbeEngine.compareVersions("1.0", "1.0.0"), .orderedSame)
        XCTAssertEqual(FastBinaryProbeEngine.compareVersions("1.2.3", "1.2.4"), .orderedAscending)
    }

    func testMachOInspectorOnSystemBinary() {
        #if os(macOS)
        let zshPath = "/bin/zsh"
        if FileManager.default.fileExists(atPath: zshPath) {
            let archInfo = MachOInspector.inspect(path: zshPath)
            XCTAssertNotEqual(archInfo, .unknown)
            #if arch(arm64)
            XCTAssertTrue(archInfo.supports(arch: "arm64"))
            #endif
        }
        #endif
    }

    func testProbeMissingBinaryRemediation() {
        let nonExistentSpec = BinaryProbeSpec(
            executableName: "nonexistent-test-cli",
            searchPaths: ["/tmp/nonexistent-test-cli-path"],
            minVersion: "1.0.0",
            requiredArch: "arm64"
        )
        let result = FastBinaryProbeEngine.probe(spec: nonExistentSpec)
        XCTAssertFalse(result.ok)
        XCTAssertNil(result.resolvedPath)
        guard case let .missing(paths) = result.failure else {
            XCTFail("Expected .missing failure, got \(String(describing: result.failure))")
            return
        }
        XCTAssertEqual(paths, ["/tmp/nonexistent-test-cli-path"])
        XCTAssertNotNil(result.remediation)
        XCTAssertTrue(result.remediation?.prescription.contains("Install nonexistent-test-cli") == true)
        XCTAssertTrue(result.remediation?.actionCommand?.contains("app-build-manager ship") == true)
    }

    func testProbePermissionDeniedRemediation() throws {
        #if os(macOS)
        let tmpFile = "/tmp/test_no_exec_\(UUID().uuidString).bin"
        try "dummy".write(toFile: tmpFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: tmpFile) }

        chmod(tmpFile, 0o644)

        let spec = BinaryProbeSpec(
            executableName: "test-no-exec",
            searchPaths: [tmpFile]
        )
        let result = FastBinaryProbeEngine.probe(spec: spec)
        XCTAssertFalse(result.ok)
        guard case let .permissionDenied(path) = result.failure else {
            XCTFail("Expected .permissionDenied, got \(String(describing: result.failure))")
            return
        }
        XCTAssertEqual(path, tmpFile)
        XCTAssertEqual(result.remediation?.actionCommand, "chmod +x \(tmpFile)")
        #endif
    }

    func testProbeArchMismatchRemediation() throws {
        #if os(macOS)
        let zshPath = "/bin/zsh"
        guard FileManager.default.fileExists(atPath: zshPath) else { return }

        let spec = BinaryProbeSpec(
            executableName: "zsh",
            searchPaths: [zshPath],
            requiredArch: "riscv64"
        )
        let result = FastBinaryProbeEngine.probe(spec: spec)
        XCTAssertFalse(result.ok)
        guard case let .architectureMismatch(_, _, req) = result.failure else {
            XCTFail("Expected .architectureMismatch, got \(String(describing: result.failure))")
            return
        }
        XCTAssertEqual(req, "riscv64")
        XCTAssertTrue(result.remediation?.prescription.contains("recompile for riscv64") == true)
        #endif
    }

    func testProbeAuditorIntegration() {
        let probe = HubServiceProbe.probeAuditor()
        // Fast pre-flight check must finish quickly (< 1000ms even under heavy system load)
        XCTAssertLessThanOrEqual(probe.durationMs, 1000)

        // If auditor is not installed, result must have clean remediation
        if !probe.ok {
            XCTAssertNotNil(probe.remediation)
            XCTAssertFalse(probe.remediation?.prescription.isEmpty ?? true)
        }
    }
}

