import Testing
import Foundation
@testable import TestingAdapterKit

@Suite("TestProcessRunnerTests")
struct TestProcessRunnerTests {

    @Test("정상 명령 동기 실행 및 stdout 캡처")
    func testBasicExecution() {
        let result = TestProcessRunner.run(
            executable: "/bin/echo",
            arguments: ["Hello", "TestingAdapterKit"]
        )

        #expect(result.exitCode == 0)
        #expect(result.isSuccess == true)
        #expect(result.timedOut == false)
        #expect(result.trimmedStdout == "Hello TestingAdapterKit")
        #expect(result.duration >= 0)
    }

    @Test("정상 명령 비동기 실행 (runAsync)")
    func testAsyncExecution() async {
        let result = await TestProcessRunner.runAsync(
            executable: "/bin/echo",
            arguments: ["Async", "Execution"]
        )

        #expect(result.exitCode == 0)
        #expect(result.isSuccess == true)
        #expect(result.timedOut == false)
        #expect(result.trimmedStdout == "Async Execution")
        #expect(result.duration >= 0)
    }

    @Test("비정상 종료 코드(exitCode != 0) 캡처")
    func testExitCodeCapture() {
        let result = TestProcessRunner.runShell("exit 42")

        #expect(result.exitCode == 42)
        #expect(result.isSuccess == false)
        #expect(result.timedOut == false)
    }

    @Test("타임아웃 강제 및 데드락 방지 검증")
    func testTimeoutEnforcement() {
        let timeout: TimeInterval = 0.3
        let result = TestProcessRunner.run(
            executable: "/bin/sleep",
            arguments: ["5"],
            timeout: timeout
        )

        #expect(result.timedOut == true)
        #expect(result.isSuccess == false)
        #expect(result.duration >= 0.25)
    }

    @Test("비동기 타임아웃 검증")
    func testAsyncTimeoutEnforcement() async {
        let timeout: TimeInterval = 0.3
        let result = await TestProcessRunner.runAsync(
            executable: "/bin/sleep",
            arguments: ["5"],
            timeout: timeout
        )

        #expect(result.timedOut == true)
        #expect(result.isSuccess == false)
        #expect(result.duration >= 0.25)
    }

    @Test("표준 에러(stderr) 및 combinedOutput 캡처")
    func testStderrCapture() {
        let result = TestProcessRunner.runShell("echo 'error log' >&2")

        #expect(result.exitCode == 0)
        #expect(result.trimmedStderr == "error log")
        #expect(result.combinedOutput.contains("error log"))
    }

    @Test("표준 입력(stdin) 데이터 전달 검증")
    func testStdinPassing() {
        let inputString = "pipeline-input-payload"
        let inputData = inputString.data(using: .utf8)

        let result = TestProcessRunner.run(
            executable: "/bin/cat",
            input: inputData
        )

        #expect(result.exitCode == 0)
        #expect(result.trimmedStdout == inputString)
    }

    @Test("64KB 초과 대용량 출력 스트림 데드락 방지 검증")
    func testLargeOutputDeadlockImmunity() {
        // 1000줄 x 약 100자 = 약 100KB (파이프 기본 버퍼 64KB 초과)
        let script = "for i in $(seq 1 1000); do echo \"Line $i: AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\"; done"
        let result = TestProcessRunner.runShell(script, timeout: 5.0)

        #expect(result.exitCode == 0)
        #expect(result.timedOut == false)
        #expect(result.stdout.count > 65536)
        #expect(result.stdout.contains("Line 1000:"))
    }
}
