import Foundation
import XCTest

final class ManifestCheckCLITests: XCTestCase {
    func testValidManifestReturnsExitZeroAndJSONEnvelope() throws {
        let result = try runCLI([
            "validate",
            fixture("valid-world-map.json").path,
            "--asset-root", fixturesRoot.path,
            "--json",
        ])

        XCTAssertEqual(result.status, 0, result.stderr)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: result.stdout) as? [String: Any])
        XCTAssertEqual(json["valid"] as? Bool, true)
        XCTAssertEqual((json["diagnostics"] as? [[String: Any]])?.count, 0)
    }

    func testInvalidManifestReturnsExitOneAndStableCode() throws {
        let result = try runCLI([
            "validate",
            fixture("invalid-reference-runtime.json").path,
            "--asset-root", fixturesRoot.path,
            "--json",
        ])

        XCTAssertEqual(result.status, 1, result.stderr)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: result.stdout) as? [String: Any])
        let diagnostics = try XCTUnwrap(json["diagnostics"] as? [[String: Any]])
        XCTAssertEqual(diagnostics.first?["code"] as? String, "GUI002_REFERENCE_IN_RUNTIME")
    }

    func testMissingInputReturnsExitSixtySix() throws {
        let result = try runCLI([
            "validate",
            fixturesRoot.appendingPathComponent("missing.json").path,
            "--asset-root", fixturesRoot.path,
            "--json",
        ])
        XCTAssertEqual(result.status, 66)
    }

    func testUsageErrorReturnsExitSixtyFour() throws {
        let result = try runCLI([])
        XCTAssertEqual(result.status, 64)
    }

    private func runCLI(_ arguments: [String]) throws -> (status: Int32, stdout: Data, stderr: String) {
        let process = Process()
        process.executableURL = try executableURL()
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        return (
            process.terminationStatus,
            stdout.fileHandleForReading.readDataToEndOfFile(),
            String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        )
    }

    private func executableURL() throws -> URL {
        let buildRoot = packageRoot.appendingPathComponent(".build", isDirectory: true)
        let enumerator = try XCTUnwrap(
            FileManager.default.enumerator(
                at: buildRoot,
                includingPropertiesForKeys: [.isExecutableKey, .isRegularFileKey]
            )
        )
        for case let url as URL in enumerator where url.lastPathComponent == "game-ui-manifest-check" {
            let values = try url.resourceValues(forKeys: [.isExecutableKey, .isRegularFileKey])
            if values.isExecutable == true, values.isRegularFile == true {
                return url
            }
        }
        XCTFail("game-ui-manifest-check executable was not built")
        throw CocoaError(.fileNoSuchFile)
    }

    private func fixture(_ name: String) -> URL {
        fixturesRoot.appendingPathComponent(name)
    }

    private var fixturesRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
    }

    private var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
