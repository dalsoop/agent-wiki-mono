import XCTest
import os
@testable import CommandKit

final class CommandKitTests: XCTestCase {
    func testResultOkOnZeroExit() {
        XCTAssertTrue(CommandResult(stdout: "", stderr: "", exitCode: 0).ok)
        XCTAssertFalse(CommandResult(stdout: "", stderr: "", exitCode: 1).ok)
    }

    func testTrimmedStdout() {
        XCTAssertEqual(CommandResult(stdout: "hi\n", stderr: "", exitCode: 0).trimmedStdout, "hi")
    }

    func testProcessWaitDrainsEcho() {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/echo")
        proc.arguments = ["hello"]
        let out = Pipe()
        let err = Pipe()
        proc.standardOutput = out
        proc.standardError = err
        try! proc.run()
        let (data, _) = ProcessWait.untilExit(proc, stdout: out, stderr: err, seconds: 5)
        XCTAssertEqual(String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), "hello")
    }

    func testProcessRunnerEcho() async {
        let r = await ProcessCommandRunner().run("/bin/echo", ["hello"])
        XCTAssertEqual(r.trimmedStdout, "hello")
        XCTAssertTrue(r.ok)
    }

    func testProcessRunnerFalseExitsNonZero() async {
        let r = await ProcessCommandRunner().run("/usr/bin/false", [])
        XCTAssertFalse(r.ok)
        XCTAssertEqual(r.exitCode, 1)
    }

    func testProcessRunnerInputAndLines() async {
        final class Box: Sendable {
            private let lock = OSAllocatedUnfairLock(initialState: [String]())
            func append(_ line: String) {
                lock.withLock { $0.append(line) }
            }
            var value: [String] {
                lock.withLock { $0 }
            }
        }
        let box = Box()
        let r = await ProcessCommandRunner().run(
            "/bin/cat",
            [],
            input: Data("line1\nline2\n".utf8),
            timeout: 5
        ) { line in
            box.append(line)
        }
        XCTAssertTrue(r.ok)
        XCTAssertEqual(r.stdout, "line1\nline2\n")
        XCTAssertEqual(box.value, ["line1", "line2"])
        XCTAssertFalse(r.timedOut)
    }

    func testProcessRunnerTimeout() async {
        let r = await ProcessCommandRunner().run(
            "/bin/sleep",
            ["5"],
            timeout: 0.05
        )
        XCTAssertTrue(r.timedOut)
        XCTAssertEqual(r.exitCode, 124)
        XCTAssertTrue(r.stderr.contains("timed out"))
    }

    func testSyncRunnerEcho() {
        let r = CommandKitSync.run("/bin/echo", ["hello"], timeout: 10)
        XCTAssertEqual(r.trimmedStdout, "hello")
        XCTAssertTrue(r.ok)
    }

    func testSyncRunnerFalseExitsNonZero() {
        let r = CommandKitSync.run("/usr/bin/false", [], timeout: 10)
        XCTAssertFalse(r.ok)
        XCTAssertEqual(r.exitCode, 1)
    }

    func testSyncRunnerTimeout() {
        let r = CommandKitSync.run("/bin/sleep", ["5"], timeout: 0.05)
        XCTAssertTrue(r.timedOut)
        XCTAssertEqual(r.exitCode, 124)
        XCTAssertTrue(r.stderr.contains("timed out"))
    }

    func testSyncRunnerInputAndEnv() {
        let inputData = Data("hello sync input\n".utf8)
        let r = CommandKitSync.run("/bin/cat", [], input: inputData, timeout: 5)
        XCTAssertTrue(r.ok)
        XCTAssertEqual(r.trimmedStdout, "hello sync input")

        let envResult = CommandKitSync.run(
            "/usr/bin/env",
            [],
            environment: ["TEST_SYNC_KEY": "test_sync_val"],
            timeout: 5
        )
        XCTAssertTrue(envResult.ok)
        XCTAssertTrue(envResult.stdout.contains("TEST_SYNC_KEY=test_sync_val"))
    }

    /// stdin 을 읽는 명령이 부모 stdin 을 상속해 무한 블로킹하지 않아야 한다(→ /dev/null EOF).
    /// 수정 전이라면 `cat` 이 EOF 를 못 받아 이 테스트가 hang 한다(회귀 감지).
    func testRunDoesNotHangOnStdinReadingCommand() {
        let r = ShellCommand.run("cat")   // stdin=/dev/null → 즉시 EOF, exit 0
        XCTAssertEqual(r.exitCode, 0)
    }

    func testRunDrainsLargeStdoutAndStderrWithoutPipeDeadlock() {
        let byteCount = 128 * 1_024
        let command = "head -c \(byteCount) /dev/zero | tr '\\0' o; "
            + "head -c \(byteCount) /dev/zero | tr '\\0' e >&2"

        let r = ShellCommand.run(command, timeout: 10)

        XCTAssertEqual(r.exitCode, 0)
        XCTAssertEqual(r.stdout.utf8.count, byteCount)
        XCTAssertEqual(r.stderr.utf8.count, byteCount)
        XCTAssertTrue(r.stdout.allSatisfy { $0 == "o" })
        XCTAssertTrue(r.stderr.allSatisfy { $0 == "e" })
    }

    func testStreamDoesNotHangOnStdinReadingCommand() async {
        let code = await ShellCommand.stream("head -c 10", timeout: 10) { _ in }
        XCTAssertEqual(code, 0)   // 타임아웃(SIGTERM=15)이 아니라 정상 종료여야 함
    }

    func testStreamLifecycleWaitsForEnteredReadAndFinalDrainBeforeCompletion() async {
        let entered = expectation(description: "read callback entered")
        let gate = DispatchSemaphore(value: 0)
        let output = LockedOutput()
        let completion = CompletionProbe()
        let lifecycle = StreamOutputLifecycle { output.append($0) }

        lifecycle.receive {
            entered.fulfill()
            gate.wait()
            return Data("Preparing...\n".utf8)
        }
        await fulfillment(of: [entered])

        lifecycle.complete(
            exitCode: 0,
            finalRead: { Data("AST extraction: 3/3".utf8) },
            onComplete: { completion.complete(exitCode: $0) }
        )
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertFalse(completion.isComplete)

        gate.signal()
        await completion.wait()
        XCTAssertEqual(completion.exitCode, 0)
        XCTAssertEqual(output.value, "Preparing...\nAST extraction: 3/3")
    }

    func testStreamPreservesFinalOutputWithoutNewline() async {
        let output = LockedOutput()
        let code = await ShellCommand.stream("printf 'AST extraction: 4/4'") {
            output.append($0)
        }

        XCTAssertEqual(code, 0)
        XCTAssertEqual(output.value, "AST extraction: 4/4")
    }

    func testStreamTimeoutStillTerminatesProcess() async {
        let output = LockedOutput()
        let code = await ShellCommand.stream("sleep 5", timeout: 0.05) {
            output.append($0)
        }

        XCTAssertNotEqual(code, 0)
        XCTAssertTrue(output.value.contains("시간 초과"))
    }

    func testStreamCancellationStillTerminatesProcess() async {
        let task = Task {
            await ShellCommand.stream("sleep 5") { _ in }
        }
        try? await Task.sleep(for: .milliseconds(50))
        task.cancel()

        let code = await task.value
        XCTAssertNotEqual(code, 0)
    }

    func testStreamDoesNotWaitForDescendantHoldingPipeOpen() async {
        let output = LockedOutput()
        let clock = ContinuousClock()
        let started = clock.now

        // 정상 경로의 host scheduling 지연은 허용하되, descendant pipe EOF를 기다리는
        // 회귀는 30초 fixture와 20초 gate로 명확히 구분한다.
        let code = await ShellCommand.stream("sleep 30 &!; printf tail") { output.append($0) }

        XCTAssertEqual(code, 0)
        XCTAssertEqual(output.value, "tail")
        XCTAssertLessThan(started.duration(to: clock.now), .seconds(20))
    }

    func testStreamReleasesOutputClosureAfterSuccessDespiteLongTimeout() async {
        let weakProbe = WeakRetentionProbe()
        do {
            let probe = RetentionProbe()
            weakProbe.value = probe
            let code = await ShellCommand.stream("true", timeout: 30) { _ in
                _ = probe
            }
            XCTAssertEqual(code, 0)
        }

        for _ in 0..<50 where weakProbe.value != nil {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNil(weakProbe.value)
    }

    func testBoundedProcessLimiterConcurrency() async throws {
        let limiter = BoundedProcessLimiter(maxConcurrent: 2)
        let inFlightCounter = OSAllocatedUnfairLock(initialState: 0)
        let maxObservedInFlight = OSAllocatedUnfairLock(initialState: 0)

        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<6 {
                group.addTask {
                    try await limiter.withLimit {
                        let current = inFlightCounter.withLock { count -> Int in
                            count += 1
                            return count
                        }
                        maxObservedInFlight.withLock { maxCount in
                            if current > maxCount { maxCount = current }
                        }
                        try await Task.sleep(nanoseconds: 20_000_000)
                        inFlightCounter.withLock { count in
                            count -= 1
                        }
                    }
                }
            }
            try await group.waitForAll()
        }

        XCTAssertLessThanOrEqual(maxObservedInFlight.withLock { $0 }, 2)
    }

    func testBoundedProcessLimiterCancellation() async throws {
        let limiter = BoundedProcessLimiter(maxConcurrent: 1)
        try await limiter.acquire()

        let task = Task {
            try await limiter.acquire()
        }

        // Wait slightly so the task enters the wait queue
        try await Task.sleep(nanoseconds: 20_000_000)
        let waitingBefore = await limiter.waitingCount
        XCTAssertEqual(waitingBefore, 1)

        task.cancel()

        do {
            try await task.value
            XCTFail("Expected CancellationError")
        } catch is CancellationError {
            // Success
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let waitingAfter = await limiter.waitingCount
        XCTAssertEqual(waitingAfter, 0)
        await limiter.release()
    }
}

private final class RetentionProbe: @unchecked Sendable {}

private final class WeakRetentionProbe {
    weak var value: RetentionProbe?
}

private final class LockedOutput: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = ""

    var value: String {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ chunk: String) {
        lock.lock()
        storage += chunk
        lock.unlock()
    }
}

private final class CompletionProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?
    private var completed = false
    private(set) var exitCode: Int32?

    var isComplete: Bool {
        lock.lock()
        defer { lock.unlock() }
        return completed
    }

    func complete(exitCode: Int32) {
        lock.lock()
        completed = true
        self.exitCode = exitCode
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume()
    }

    func wait() async {
        if isComplete { return }
        await withCheckedContinuation { continuation in
            lock.lock()
            if completed {
                lock.unlock()
                continuation.resume()
            } else {
                self.continuation = continuation
                lock.unlock()
            }
        }
    }
}
