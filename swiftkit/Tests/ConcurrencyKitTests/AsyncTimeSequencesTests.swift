import XCTest
import os
@testable import ConcurrencyKit

final class AsyncTimeSequencesTests: XCTestCase {

    // MARK: - Debounce Tests

    func testDebounceEmitsOnlyLastEventAfterQuietPeriod() async {
        let (stream, continuation) = AsyncStream<Int>.makeStream()

        let debounced = stream.debounce(for: .milliseconds(40))

        let expectation = expectation(description: "Collected debounced values")
        let collectedValues = OSAllocatedUnfairLock<[Int]>(initialState: [])

        let consumeTask = Task {
            for await value in debounced {
                collectedValues.withLock { $0.append(value) }
            }
            expectation.fulfill()
        }

        // 연속해서 10ms 간격으로 1, 2, 3 방출 (debounce 40ms보다 짧음)
        continuation.yield(1)
        try? await Task.sleep(for: .milliseconds(10))
        continuation.yield(2)
        try? await Task.sleep(for: .milliseconds(10))
        continuation.yield(3)

        // 3이 방출될 때까지 대기
        try? await Task.sleep(for: .milliseconds(60))
        continuation.finish()

        await fulfillment(of: [expectation], timeout: 2.0)
        _ = await consumeTask.result

        XCTAssertEqual(collectedValues.withLock { $0 }, [3])
    }

    func testDebounceEmitsMultipleEventsWithSufficientIntervals() async {
        let (stream, continuation) = AsyncStream<String>.makeStream()

        let debounced = stream.debounce(for: .milliseconds(30))

        let expectation = expectation(description: "Collected spaced debounced values")
        let collectedValues = OSAllocatedUnfairLock<[String]>(initialState: [])

        let consumeTask = Task {
            for await value in debounced {
                collectedValues.withLock { $0.append(value) }
            }
            expectation.fulfill()
        }

        continuation.yield("A")
        try? await Task.sleep(for: .milliseconds(50)) // 30ms 초과 -> "A" 방출

        continuation.yield("B")
        try? await Task.sleep(for: .milliseconds(50)) // 30ms 초과 -> "B" 방출

        continuation.finish()

        await fulfillment(of: [expectation], timeout: 2.0)
        _ = await consumeTask.result

        XCTAssertEqual(collectedValues.withLock { $0 }, ["A", "B"])
    }

    func testDebounceFinishFlushesPendingEvent() async {
        let (stream, continuation) = AsyncStream<Int>.makeStream()

        let debounced = stream.debounce(for: .milliseconds(30))

        let expectation = expectation(description: "Flushed on finish")
        let collectedValues = OSAllocatedUnfairLock<[Int]>(initialState: [])

        let consumeTask = Task {
            for await value in debounced {
                collectedValues.withLock { $0.append(value) }
            }
            expectation.fulfill()
        }

        continuation.yield(99)
        continuation.finish() // 바로 finish해도 대기 중이던 99가 타이머 만료 후 방출되어야 함

        await fulfillment(of: [expectation], timeout: 2.0)
        _ = await consumeTask.result

        XCTAssertEqual(collectedValues.withLock { $0 }, [99])
    }

    func testDebounceCancellation() async {
        let (stream, continuation) = AsyncStream<Int>.makeStream()

        let debounced = stream.debounce(for: .milliseconds(50))
        let collectedValues = OSAllocatedUnfairLock<[Int]>(initialState: [])

        let consumeTask = Task {
            for await value in debounced {
                collectedValues.withLock { $0.append(value) }
            }
        }

        continuation.yield(1)
        try? await Task.sleep(for: .milliseconds(10))
        consumeTask.cancel() // 중간 취소

        try? await Task.sleep(for: .milliseconds(70))
        continuation.finish()
        _ = await consumeTask.result

        // 취소되었으므로 1이 방출되지 않아야 함
        XCTAssertEqual(collectedValues.withLock { $0 }, [])
    }

    // MARK: - Throttle Tests (latest: false)

    func testThrottleLeadingOnlyWhenLatestFalse() async {
        let (stream, continuation) = AsyncStream<Int>.makeStream()

        let throttled = stream.throttle(for: .milliseconds(50), latest: false)

        let expectation = expectation(description: "Collected throttle latest=false values")
        let collectedValues = OSAllocatedUnfairLock<[Int]>(initialState: [])

        let consumeTask = Task {
            for await value in throttled {
                collectedValues.withLock { $0.append(value) }
            }
            expectation.fulfill()
        }

        // t = 0ms: 1 방출 (leading)
        continuation.yield(1)
        // t = 15ms: 2 무시됨
        try? await Task.sleep(for: .milliseconds(15))
        continuation.yield(2)
        // t = 30ms: 3 무시됨
        try? await Task.sleep(for: .milliseconds(15))
        continuation.yield(3)

        // t = 70ms (50ms 윈도우 경과 후): 4 방출 (새 윈도우 leading)
        try? await Task.sleep(for: .milliseconds(40))
        continuation.yield(4)

        try? await Task.sleep(for: .milliseconds(60))
        continuation.finish()

        await fulfillment(of: [expectation], timeout: 2.0)
        _ = await consumeTask.result

        XCTAssertEqual(collectedValues.withLock { $0 }, [1, 4])
    }

    // MARK: - Throttle Tests (latest: true)

    func testThrottleLeadingAndTrailingWhenLatestTrue() async {
        let (stream, continuation) = AsyncStream<Int>.makeStream()

        let throttled = stream.throttle(for: .milliseconds(50), latest: true)

        let expectation = expectation(description: "Collected throttle latest=true values")
        let collectedValues = OSAllocatedUnfairLock<[Int]>(initialState: [])

        let consumeTask = Task {
            for await value in throttled {
                collectedValues.withLock { $0.append(value) }
            }
            expectation.fulfill()
        }

        // t = 0ms: 1 방출 (leading)
        continuation.yield(1)
        // t = 15ms: 2 (trailing 후보)
        try? await Task.sleep(for: .milliseconds(15))
        continuation.yield(2)
        // t = 30ms: 3 (trailing 후보 갱신)
        try? await Task.sleep(for: .milliseconds(15))
        continuation.yield(3)

        // 윈도우 만료(50ms) 시 3이 trailing으로 방출됨
        try? await Task.sleep(for: .milliseconds(70))
        continuation.finish()

        await fulfillment(of: [expectation], timeout: 2.0)
        _ = await consumeTask.result

        XCTAssertEqual(collectedValues.withLock { $0 }, [1, 3])
    }

    func testThrottleLatestTrueWithoutTrailingEvent() async {
        let (stream, continuation) = AsyncStream<String>.makeStream()

        let throttled = stream.throttle(for: .milliseconds(40), latest: true)

        let expectation = expectation(description: "Collected throttle isolated events")
        let collectedValues = OSAllocatedUnfairLock<[String]>(initialState: [])

        let consumeTask = Task {
            for await value in throttled {
                collectedValues.withLock { $0.append(value) }
            }
            expectation.fulfill()
        }

        // t = 0ms: "A" 방출 (leading)
        continuation.yield("A")

        // 윈도우 동안 아무것도 안 옴 -> 60ms 후 "B" 방출
        try? await Task.sleep(for: .milliseconds(60))
        continuation.yield("B")

        try? await Task.sleep(for: .milliseconds(60))
        continuation.finish()

        await fulfillment(of: [expectation], timeout: 2.0)
        _ = await consumeTask.result

        XCTAssertEqual(collectedValues.withLock { $0 }, ["A", "B"])
    }

    func testThrottleCancellation() async {
        let (stream, continuation) = AsyncStream<Int>.makeStream()

        let throttled = stream.throttle(for: .milliseconds(50), latest: true)
        let collectedValues = OSAllocatedUnfairLock<[Int]>(initialState: [])

        let consumeTask = Task {
            for await value in throttled {
                collectedValues.withLock { $0.append(value) }
            }
        }

        continuation.yield(1) // 즉시 방출
        try? await Task.sleep(for: .milliseconds(10))
        continuation.yield(2) // trailing 후보

        consumeTask.cancel() // 소비 취소

        try? await Task.sleep(for: .milliseconds(70))
        continuation.finish()
        _ = await consumeTask.result

        // 취소되었으므로 최초의 1만 수신되고 2는 수신되지 않거나 더 이상 추가 수신 없음
        XCTAssertEqual(collectedValues.withLock { $0 }, [1])
    }
}
