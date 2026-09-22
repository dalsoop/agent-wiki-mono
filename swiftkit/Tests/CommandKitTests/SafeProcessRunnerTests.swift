import XCTest
import Foundation
@testable import CommandKit

final class SafeProcessRunnerTests: XCTestCase {

    func testSafeProcessRunnerInstantiation() {
        let runner = SafeProcessRunner()
        XCTAssertNotNil(runner)
        let polymorphicRunner: any CommandRunning = runner
        XCTAssertNotNil(polymorphicRunner)
    }

    func testSyncExecutionWithLabeledArguments() {
        let result = SafeProcessRunner.run(
            executable: "/bin/echo",
            arguments: ["hello", "world"]
        )
        XCTAssertTrue(result.ok)
        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.trimmedStdout, "hello world")
        XCTAssertFalse(result.timedOut)
        XCTAssertEqual(result.combinedOutput, "hello world\n")
    }

    func testSyncExecutionWithPositionalArguments() {
        let result = SafeProcessRunner.run("/bin/echo", ["positional", "call"])
        XCTAssertTrue(result.ok)
        XCTAssertEqual(result.trimmedStdout, "positional call")
    }

    func testRunSyncExplicit() {
        let result = SafeProcessRunner.runSync(
            executable: "/bin/echo",
            arguments: ["explicit", "sync"]
        )
        XCTAssertTrue(result.ok)
        XCTAssertEqual(result.trimmedStdout, "explicit sync")
    }

    func testRunSyncThrowingSuccess() throws {
        let result = try SafeProcessRunner.runSyncThrowing(
            executable: "/bin/echo",
            arguments: ["throwing", "success"]
        )
        XCTAssertTrue(result.ok)
        XCTAssertEqual(result.trimmedStdout, "throwing success")
    }

    func testRunSyncThrowingFailure() {
        XCTAssertThrowsError(
            try SafeProcessRunner.runSyncThrowing(
                executable: "/usr/bin/false"
            )
        ) { error in
            guard case CommandError.nonZeroExit(let exitCode, _) = error else {
                XCTFail("Expected CommandError.nonZeroExit, got \(error)")
                return
            }
            XCTAssertEqual(exitCode, 1)
        }
    }

    func testAsyncExecutionNonThrowing() async {
        let result = await SafeProcessRunner.runAsync(
            executable: "/bin/echo",
            arguments: ["async", "hello"]
        )
        XCTAssertTrue(result.ok)
        XCTAssertEqual(result.trimmedStdout, "async hello")
    }

    func testAsyncExecutionThrowingSuccess() async throws {
        let result = try await SafeProcessRunner.run(
            executable: "/bin/echo",
            arguments: ["async", "throws", "success"]
        )
        XCTAssertTrue(result.ok)
        XCTAssertEqual(result.trimmedStdout, "async throws success")
    }

    func testAsyncExecutionThrowingFailure() async {
        do {
            _ = try await SafeProcessRunner.run(
                executable: "/usr/bin/false",
                throwOnNonZeroExit: true
            )
            XCTFail("Expected run to throw on non-zero exit")
        } catch {
            guard case CommandError.nonZeroExit(let exitCode, _) = error else {
                XCTFail("Expected CommandError.nonZeroExit, got \(error)")
                return
            }
            XCTAssertEqual(exitCode, 1)
        }
    }

    func testAsyncExecutionNonZeroExitWithoutThrow() async throws {
        let result = try await SafeProcessRunner.run(
            executable: "/usr/bin/false",
            throwOnNonZeroExit: false
        )
        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.exitCode, 1)
    }

    func testRunShellSync() {
        let result = SafeProcessRunner.runShell("echo shell-sync-test")
        XCTAssertTrue(result.ok)
        XCTAssertEqual(result.trimmedStdout, "shell-sync-test")
    }

    func testRunShellAsync() async {
        let result = await SafeProcessRunner.runShellAsync("echo shell-async-test")
        XCTAssertTrue(result.ok)
        XCTAssertEqual(result.trimmedStdout, "shell-async-test")
    }

    func testRunShellAsyncThrowing() async throws {
        let result = try await SafeProcessRunner.runShell("echo shell-throwing-test")
        XCTAssertTrue(result.ok)
        XCTAssertEqual(result.trimmedStdout, "shell-throwing-test")
    }

    func testProcessResultConveniences() {
        let success = ProcessResult(stdout: "out\n", stderr: "warn\n", exitCode: 0, timedOut: false)
        XCTAssertTrue(success.ok)
        XCTAssertTrue(success.isSuccess)
        XCTAssertEqual(success.trimmedStdout, "out")
        XCTAssertEqual(success.trimmedStderr, "warn")
        XCTAssertEqual(success.combinedOutput, "out\nwarn\n")

        let failure = ProcessResult(stdout: "", stderr: "error", exitCode: 1, timedOut: false)
        XCTAssertFalse(failure.ok)
        XCTAssertFalse(failure.isSuccess)

        let timedOut = ProcessResult(stdout: "", stderr: "", exitCode: 124, timedOut: true)
        XCTAssertFalse(timedOut.ok)
        XCTAssertFalse(timedOut.isSuccess)
    }

    func testProcessResultLinesAndData() {
        let result = ProcessResult(stdout: "line1\n  \nline2\n", stderr: "err1\n", exitCode: 0)
        XCTAssertEqual(result.stdoutData, Data("line1\n  \nline2\n".utf8))
        XCTAssertEqual(result.stderrData, Data("err1\n".utf8))
        XCTAssertEqual(result.lines, ["line1", "  ", "line2", ""])
        XCTAssertEqual(result.nonEmptyLines, ["line1", "line2"])
    }

    func testSyncWorkingDirectoryPathAndInputText() {
        let result = SafeProcessRunner.run(
            executable: "/bin/cat",
            workingDirectoryPath: "/tmp",
            inputText: "piped-data"
        )
        XCTAssertTrue(result.ok)
        XCTAssertEqual(result.trimmedStdout, "piped-data")
    }

    func testRunSyncThrowingPositionalAndSpec() throws {
        let posResult = try SafeProcessRunner.runSyncThrowing("/bin/echo", ["hello-positional"])
        XCTAssertTrue(posResult.ok)
        XCTAssertEqual(posResult.trimmedStdout, "hello-positional")

        let spec = CommandSpecification("/bin/echo", ["hello-spec"])
        let specResult = try SafeProcessRunner.runSyncThrowing(spec)
        XCTAssertTrue(specResult.ok)
        XCTAssertEqual(specResult.trimmedStdout, "hello-spec")
    }

    func testRunSyncOutput() throws {
        let out1 = try SafeProcessRunner.runSyncOutput(executable: "/bin/echo", arguments: ["sync-out"])
        XCTAssertEqual(out1, "sync-out")

        let out2 = try SafeProcessRunner.runSyncOutput("/bin/echo", ["sync-pos-out"])
        XCTAssertEqual(out2, "sync-pos-out")

        let out3 = try SafeProcessRunner.runSyncOutput(CommandSpecification("/bin/echo", ["sync-spec-out"]))
        XCTAssertEqual(out3, "sync-spec-out")
    }

    func testAsyncWorkingDirectoryPathAndInputText() async throws {
        let result = try await SafeProcessRunner.run(
            executable: "/bin/cat",
            workingDirectoryPath: "/tmp",
            inputText: "async-piped-data"
        )
        XCTAssertTrue(result.ok)
        XCTAssertEqual(result.trimmedStdout, "async-piped-data")
    }

    func testRunThrowingPositionalAndSpec() async throws {
        let posResult = try await SafeProcessRunner.runThrowing("/bin/echo", ["async-pos"])
        XCTAssertTrue(posResult.ok)
        XCTAssertEqual(posResult.trimmedStdout, "async-pos")

        let spec = CommandSpecification("/bin/echo", ["async-spec"])
        let specResult = try await SafeProcessRunner.runThrowing(spec)
        XCTAssertTrue(specResult.ok)
        XCTAssertEqual(specResult.trimmedStdout, "async-spec")
    }

    func testRunOutput() async throws {
        let out1 = try await SafeProcessRunner.runOutput(executable: "/bin/echo", arguments: ["async-out"])
        XCTAssertEqual(out1, "async-out")

        let out2 = try await SafeProcessRunner.runOutput("/bin/echo", ["async-pos-out"])
        XCTAssertEqual(out2, "async-pos-out")

        let out3 = try await SafeProcessRunner.runOutput(CommandSpecification("/bin/echo", ["async-spec-out"]))
        XCTAssertEqual(out3, "async-spec-out")
    }

    func testRunShellSyncOutputAndRunShellOutput() async throws {
        let syncOut = try SafeProcessRunner.runShellSyncOutput("echo shell-sync-out")
        XCTAssertEqual(syncOut, "shell-sync-out")

        let asyncOut = try await SafeProcessRunner.runShellOutput("echo shell-async-out")
        XCTAssertEqual(asyncOut, "shell-async-out")
    }

    func testInstanceErgonomics() async throws {
        let runner = SafeProcessRunner()
        let syncRes = runner.runSync(executable: "/bin/echo", arguments: ["instance-sync"])
        XCTAssertEqual(syncRes.trimmedStdout, "instance-sync")

        let asyncRes = try await runner.run(executable: "/bin/echo", arguments: ["instance-async"])
        XCTAssertEqual(asyncRes.trimmedStdout, "instance-async")

        let out = try await runner.runOutput(executable: "/bin/echo", arguments: ["instance-out"])
        XCTAssertEqual(out, "instance-out")
    }

    func testCommandRunningPolymorphism() async {
        let runner: any CommandRunning = SafeProcessRunner()
        let spec = CommandSpecification("/bin/echo", ["polymorphic"])
        let result = await runner.run(spec)
        XCTAssertTrue(result.ok)
        XCTAssertEqual(result.trimmedStdout, "polymorphic")
    }

    func testStreamingLines() async throws {
        var lines: [String] = []
        for try await output in SafeProcessRunner.lines(executable: "/bin/echo", arguments: ["line1\nline2"]) {
            switch output {
            case .stdout(let text):
                lines.append(text)
            case .stderr:
                break
            }
        }
        XCTAssertEqual(lines, ["line1", "line2"])
    }

    // MARK: - Safe Termination Tests

    func testKillProcessRejectsUnsafePIDs() {
        XCTAssertFalse(SafeProcessRunner.killProcess(pid: 0))
        XCTAssertFalse(SafeProcessRunner.killProcess(pid: -1))
        XCTAssertFalse(SafeProcessRunner.killProcess(pid: -123))
        XCTAssertFalse(SafeProcessRunner.killProcess(pid: 1))
    }

    func testKillProcessGroupRejectsUnsafePGIDs() {
        XCTAssertFalse(SafeProcessRunner.killProcessGroup(pgid: 0))
        XCTAssertFalse(SafeProcessRunner.killProcessGroup(pgid: -1))
        XCTAssertFalse(SafeProcessRunner.killProcessGroup(pgid: -999))
        XCTAssertFalse(SafeProcessRunner.killProcessGroup(pgid: 1))
        #if canImport(Darwin) || canImport(Glibc)
        let myPgid = getpgrp()
        XCTAssertFalse(SafeProcessRunner.killProcessGroup(pgid: myPgid), "호출자 자신의 프로세스 그룹 종료는 차단되어야 합니다")
        #endif
    }

    func testProcessAliveProbe() {
        #if canImport(Darwin) || canImport(Glibc)
        let myPid = getpid()
        XCTAssertTrue(SafeProcessRunner.isProcessAlive(pid: myPid))
        XCTAssertFalse(SafeProcessRunner.isProcessAlive(pid: 999_999_999))
        #endif
    }

    func testTerminateProcessLifecycle() async throws {
        let proc = try SafeProcessRunner.spawn("/bin/sleep", ["10"])
        let pid = proc.processIdentifier
        XCTAssertTrue(pid > 1)
        XCTAssertTrue(SafeProcessRunner.isProcessAlive(pid: pid))

        let terminated = await SafeProcessRunner.terminateProcess(pid: pid, gracePeriod: 0.1)
        XCTAssertTrue(terminated)
        XCTAssertFalse(SafeProcessRunner.isProcessAlive(pid: pid))
    }
}

