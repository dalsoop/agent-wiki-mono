import XCTest
import Foundation
@testable import CommandKit

final class WaitDelayTests: XCTestCase {
    func testShellCommandRunDoesNotHangOnGrandchildHoldingPipe() {
        let clock = ContinuousClock()
        let started = clock.now

        // 자식 셸이 백그라운드 프로세스(sleep 15)를 띄워 파일 디스크립터를 물고 있어도
        // WaitDelay(0.5s) 유예 시간 후 강제 close되어 행(hang) 없이 5초 이내에 정상 반환되어야 함.
        let r = ShellCommand.run("sleep 15 &! ; printf wait_delay_success")

        XCTAssertTrue(r.ok, "Command should succeed with exit code 0")
        XCTAssertEqual(r.trimmedStdout, "wait_delay_success")
        XCTAssertLessThan(started.duration(to: clock.now), .seconds(5))
    }

    func testShellCommandExecuteWithWaitDelayDirectProcess() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-c", "sleep 15 &! ; printf direct_exec"]
        let out = Pipe()
        let err = Pipe()
        p.standardOutput = out
        p.standardError = err
        p.standardInput = FileHandle.nullDevice

        let clock = ContinuousClock()
        let started = clock.now

        let r = ShellCommand.executeWithWaitDelay(process: p, stdout: out, stderr: err, waitDelay: 0.5)

        XCTAssertTrue(r.ok)
        XCTAssertEqual(r.trimmedStdout, "direct_exec")
        XCTAssertLessThan(started.duration(to: clock.now), .seconds(5))
    }

    func testShellCommandRunSafeDoesNotHangOnGrandchildHoldingPipe() {
        let clock = ContinuousClock()
        let started = clock.now

        let r = ShellCommand.runSafe(
            scriptTemplate: "sleep 15 &! ; printf 'safe_%s' \"$1\"",
            arguments: ["param"]
        )

        XCTAssertTrue(r.ok)
        XCTAssertEqual(r.trimmedStdout, "safe_param")
        XCTAssertLessThan(started.duration(to: clock.now), .seconds(5))
    }

    func testProcessCommandRunnerWaitDelayOnGrandchildHoldingPipe() async {
        let runner = ProcessCommandRunner()
        let clock = ContinuousClock()
        let started = clock.now

        let r = await runner.run("/bin/zsh", ["-c", "sleep 15 &! ; printf async_runner_success"])

        XCTAssertTrue(r.ok)
        XCTAssertEqual(r.trimmedStdout, "async_runner_success")
        XCTAssertLessThan(started.duration(to: clock.now), .seconds(5))
    }

    func testProcessCommandRunnerExecuteWithWaitDelaySpec() async {
        let runner = ProcessCommandRunner()
        let spec = CommandSpecification("/bin/zsh", ["-c", "sleep 15 &! ; printf spec_success"])
            .withWaitDelay(0.5)

        let clock = ContinuousClock()
        let started = clock.now

        let r = await runner.executeWithWaitDelay(spec)

        XCTAssertTrue(r.ok)
        XCTAssertEqual(r.trimmedStdout, "spec_success")
        XCTAssertLessThan(started.duration(to: clock.now), .seconds(5))
    }

    func testProcessCommandRunnerExecuteWithWaitDelayDirect() {
        let clock = ContinuousClock()
        let started = clock.now

        let r = ProcessCommandRunner.executeWithWaitDelay("/bin/zsh", ["-c", "sleep 15 &! ; printf static_exec"])

        XCTAssertTrue(r.ok)
        XCTAssertEqual(r.trimmedStdout, "static_exec")
        XCTAssertLessThan(started.duration(to: clock.now), .seconds(5))
    }

    func testNormalCommandCompletesFastWithoutWaitingFullWaitDelay() {
        let clock = ContinuousClock()
        let started = clock.now

        let r = ShellCommand.run("echo fast_output")

        XCTAssertTrue(r.ok)
        XCTAssertEqual(r.trimmedStdout, "fast_output")
        // EOF가 바로 오면 0.5초 유예시간을 다 채우지 않고 즉시 반환되어야 함
        XCTAssertLessThan(started.duration(to: clock.now), .milliseconds(400))
    }
}
