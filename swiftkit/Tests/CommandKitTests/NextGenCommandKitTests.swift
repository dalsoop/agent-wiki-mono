import XCTest
import CommandKit
import CommandKitTesting

final class NextGenCommandKitTests: XCTestCase {
    func testCommandSpecificationCreationAndMutation() {
        let spec = CommandSpecification("/usr/bin/echo", ["hello", "world"])
            .withTimeout(10)
            .withEnvironment(["TEST_ENV": "1"])
            .withWorkingDirectory(URL(fileURLWithPath: "/tmp"))

        XCTAssertEqual(spec.launchPath, "/usr/bin/echo")
        XCTAssertEqual(spec.arguments, ["hello", "world"])
        XCTAssertEqual(spec.timeout, 10)
        XCTAssertEqual(spec.environment?["TEST_ENV"], "1")
        XCTAssertEqual(spec.workingDirectoryURL?.path, "/tmp")
        XCTAssertEqual(spec.description, "/usr/bin/echo hello world")
    }

    func testCommandLineOutput() {
        let stdout = CommandLineOutput.stdout("info line")
        XCTAssertEqual(stdout.text, "info line")
        XCTAssertEqual(stdout.line, "info line")
        XCTAssertTrue(stdout.isStdout)
        XCTAssertFalse(stdout.isStderr)
        XCTAssertEqual(stdout.stream, .stdout)
        XCTAssertEqual(stdout.description, "info line")

        let stderr = CommandLineOutput.stderr("error line")
        XCTAssertTrue(stderr.isStderr)
        XCTAssertFalse(stderr.isStdout)
        XCTAssertEqual(stderr.stream, .stderr)
    }

    func testProcessEnvironmentEnriched() {
        let env = ProcessEnvironment.enriched(["PATH": "/usr/bin:/bin", "SWIFT_EXEC": "/usr/bin/swift"])
        XCTAssertNil(env["SWIFT_EXEC"], "Unusable SWIFT_EXEC must be removed by ToolchainEnvironment.sanitized")

        let path = env["PATH"] ?? ""
        let homebrewPrefix = ProcessInfo.processInfo.environment["HOMEBREW_PREFIX"] ?? {
            #if arch(arm64)
            return "/opt/homebrew"
            #else
            return "/usr/local"
            #endif
        }()
        let expectedHomebrewBin = "\(homebrewPrefix)/bin"
        XCTAssertTrue(path.contains(expectedHomebrewBin) || path.contains("/usr/local/bin"))
    }

    func testProcessCommandRunnerRunSpec() async {
        let runner = ProcessCommandRunner()
        let spec = CommandSpecification("/bin/echo", ["engine-test"])
        let result = await runner.run(spec)

        XCTAssertTrue(result.ok)
        XCTAssertEqual(result.trimmedStdout, "engine-test")
    }

    func testProcessCommandRunnerLinesStreaming() async throws {
        let runner = ProcessCommandRunner()
        let spec = CommandSpecification("/bin/echo", ["stream-line-1\nstream-line-2"])

        var collected: [String] = []
        for try await lineOutput in runner.lines(spec) {
            collected.append(lineOutput.text)
        }

        XCTAssertTrue(collected.contains("stream-line-1"))
        XCTAssertTrue(collected.contains("stream-line-2"))
    }

    func testMockCommandRunnerStubAndAssertions() async {
        let mock = MockCommandRunner()
        mock.stub(
            executable: "git",
            arguments: ["rev-parse", "HEAD"],
            stdout: "abcdef123456\n"
        )

        let result = await mock.run(CommandSpecification("git", ["rev-parse", "HEAD"]))
        XCTAssertTrue(result.ok)
        XCTAssertEqual(result.trimmedStdout, "abcdef123456")

        XCTAssertTrue(mock.assertCalled(executable: "git", arguments: ["rev-parse", "HEAD"], times: 1))
        XCTAssertTrue(mock.assertNotCalled(executable: "swift"))
        XCTAssertEqual(mock.callCount, 1)

        mock.clearCalls()
        XCTAssertEqual(mock.callCount, 0)
    }

    func testMockCommandRunnerLinesStreaming() async throws {
        let mock = MockCommandRunner()
        mock.stub(
            matcher: .executable("worker"),
            result: CommandResult(stdout: "ready\nprocessing\ndone\n", stderr: "", exitCode: 0)
        )

        var lines: [String] = []
        for try await output in mock.lines(CommandSpecification("worker", [])) {
            lines.append(output.text)
        }

        XCTAssertEqual(lines, ["ready", "processing", "done"])
        XCTAssertTrue(mock.assertCalled(matcher: .executable("worker")))
    }
}
