import XCTest
import os
@testable import ConcurrencyKit

final class ConcurrencyKitTests: XCTestCase {
    func testOSAllocatedUnfairLockExchange() {
        let lock = OSAllocatedUnfairLock(initialState: 42)
        let oldVal = lock.exchange(99)
        XCTAssertEqual(oldVal, 42)
        XCTAssertEqual(lock.withLock { $0 }, 99)
    }

    func testOnceGateSingleExecution() async {
        let gate = OnceGate()
        XCTAssertFalse(gate.isOpened)
        XCTAssertTrue(gate.open())
        XCTAssertTrue(gate.isOpened)
        XCTAssertFalse(gate.open())
        XCTAssertFalse(gate.open())
    }

    func testOnceGateConcurrentRace() async {
        let gate = OnceGate()
        let openCount = OSAllocatedUnfairLock(initialState: 0)

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<50 {
                group.addTask {
                    if gate.open() {
                        openCount.withLock { $0 += 1 }
                    }
                }
            }
        }

        XCTAssertEqual(openCount.withLock { $0 }, 1)
        XCTAssertTrue(gate.isOpened)
    }

    func testContinuationGateReturning() async {
        let resumeCount = OSAllocatedUnfairLock(initialState: 0)
        let receivedValue = OSAllocatedUnfairLock<String?>(initialState: Optional<String>.none)

        let gate = ContinuationGate<String, Never> { result in
            resumeCount.withLock { $0 += 1 }
            if case .success(let val) = result {
                receivedValue.withLock { $0 = val }
            }
        }

        XCTAssertFalse(gate.hasResumed)

        let first = gate.resume(returning: "hello")
        XCTAssertTrue(first)
        XCTAssertTrue(gate.hasResumed)

        let second = gate.resume(returning: "world")
        XCTAssertFalse(second)
        XCTAssertTrue(gate.hasResumed)

        XCTAssertEqual(resumeCount.withLock { $0 }, 1)
        XCTAssertEqual(receivedValue.withLock { $0 }, "hello")
    }

    func testContinuationGateVoidResume() async {
        let gate = ContinuationGate<Void, Never> { _ in }
        XCTAssertTrue(gate.resume())
        XCTAssertFalse(gate.resume())
        XCTAssertTrue(gate.hasResumed)
    }

    enum DummyError: Error, Equatable, Sendable {
        case failureCase
    }

    func testContinuationGateThrowing() async {
        let receivedError = OSAllocatedUnfairLock<DummyError?>(initialState: Optional<DummyError>.none)

        let gate = ContinuationGate<Int, DummyError> { result in
            if case .failure(let err) = result {
                receivedError.withLock { $0 = err }
            }
        }

        XCTAssertTrue(gate.resume(throwing: DummyError.failureCase))
        XCTAssertFalse(gate.resume(returning: 123))
        XCTAssertEqual(receivedError.withLock { $0 }, DummyError.failureCase)
    }

    func testContinuationGateConcurrentRace() async {
        let resumeCount = OSAllocatedUnfairLock(initialState: 0)
        let gate = ContinuationGate<Int, Never> { _ in
            resumeCount.withLock { $0 += 1 }
        }

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<50 {
                group.addTask {
                    gate.resume(returning: i)
                }
            }
        }

        XCTAssertEqual(resumeCount.withLock { $0 }, 1)
        XCTAssertTrue(gate.hasResumed)
    }
}
