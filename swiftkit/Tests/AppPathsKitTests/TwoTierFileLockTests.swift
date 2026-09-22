import XCTest
import os
@testable import AppPathsKit

final class TwoTierFileLockTests: XCTestCase {

    private var tempDir: URL = URL(fileURLWithPath: NSTemporaryDirectory())

    override func setUp() {
        super.setUp()
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("twotier-lock-tests-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            XCTFail("Failed to create tempDir: \(error)")
        }
    }

    override func tearDown() {
        do {
            try FileManager.default.removeItem(at: tempDir)
        } catch {
            _ = error
        }
        super.tearDown()
    }

    func testSingleThreadLockAcquisition() throws {
        let lockURL = tempDir.appendingPathComponent("test.lock")
        var executed = false

        let result = try TwoTierFileLock.withLock(at: lockURL, exclusive: true, timeout: 5.0) {
            executed = true
            return 42
        }

        XCTAssertTrue(executed)
        XCTAssertEqual(result, 42)
    }

    func testNSRecursiveLockReentrancy() throws {
        let lockURL = tempDir.appendingPathComponent("reentrant.lock")
        var depth = 0

        try TwoTierFileLock.withLock(at: lockURL, exclusive: true, timeout: 5.0) {
            depth += 1
            // Tier 1 NSRecursiveLock에 의해 동일 스레드 내 재진입이 정상 허용되어야 함
            try TwoTierFileLock.withLock(at: lockURL, exclusive: true, timeout: 5.0) {
                depth += 1
            }
        }

        XCTAssertEqual(depth, 2)
    }

    private final class SafeBox<T: Sendable>: Sendable {
        private let state: OSAllocatedUnfairLock<T>
        init(_ value: T) { self.state = OSAllocatedUnfairLock(initialState: value) }
        var value: T {
            get { state.withLock { $0 } }
            set { state.withLock { $0 = newValue } }
        }
    }

    func testMultiThreadContention() throws {
        let lockURL = tempDir.appendingPathComponent("contention.lock")
        let iterations = 20
        let box = SafeBox(0)
        let exp = expectation(description: "Contention completed")
        exp.expectedFulfillmentCount = iterations

        let queue = DispatchQueue(label: "test.contention.queue", attributes: .concurrent)

        for _ in 0..<iterations {
            queue.async {
                do {
                    try TwoTierFileLock.withLock(at: lockURL, exclusive: true, timeout: 10.0) {
                        let current = box.value
                        Thread.sleep(forTimeInterval: 0.001) // 1ms 동안 배타성 유지
                        box.value = current + 1
                    }
                    exp.fulfill()
                } catch {
                    XCTFail("Lock failed with error: \(error)")
                }
            }
        }

        wait(for: [exp], timeout: 15.0)
        XCTAssertEqual(box.value, iterations)
    }

    func testLockTimeout() throws {
        let lockURL = tempDir.appendingPathComponent("timeout.lock")
        let lockHeldExp = expectation(description: "Lock is held by thread 1")
        let semaphore = DispatchSemaphore(value: 0)
        let errorBox = SafeBox<TwoTierFileLockError?>(nil)
        let thread2Done = expectation(description: "Thread 2 timeout completed")

        let t1 = Thread {
            do {
                try TwoTierFileLock.withLock(at: lockURL, exclusive: true, timeout: 5.0) {
                    lockHeldExp.fulfill()
                    _ = semaphore.wait(timeout: .now() + 5.0)
                }
            } catch {
                XCTFail("Thread 1 lock failed: \(error)")
            }
        }
        t1.start()

        wait(for: [lockHeldExp], timeout: 5.0)

        // 다른 스레드에서 매우 짧은 타임아웃으로 취득 시도 -> 타임아웃 발생해야 함
        let t2 = Thread {
            do {
                try TwoTierFileLock.withLock(at: lockURL, exclusive: true, timeout: 0.05) {
                    XCTFail("Thread 2 should not have acquired lock")
                }
            } catch let lockError as TwoTierFileLockError {
                errorBox.value = lockError
            } catch {
                XCTFail("Unexpected error type: \(error)")
            }
            thread2Done.fulfill()
        }
        t2.start()

        wait(for: [thread2Done], timeout: 5.0)
        semaphore.signal()

        XCTAssertNotNil(errorBox.value)
        if let lockError = errorBox.value,
           case .timeout = lockError {
            // expected
        } else {
            XCTFail("Expected TwoTierFileLockError.timeout, got \(String(describing: errorBox.value))")
        }
    }

    func testSlugAndLockPathOverloads() throws {
        let slug = "test-twotier-slug"
        let home = try XCTUnwrap(tempDir)

        var ran = false
        try TwoTierFileLock.withLock(slug: slug, homeDirectory: home) {
            ran = true
        }
        XCTAssertTrue(ran)

        let lockPath = AppPaths.lockFile(slug: slug, homeDirectory: home)
        var ranPath = false
        try TwoTierFileLock.withLock(lockPath) {
            ranPath = true
        }
        XCTAssertTrue(ranPath)
    }
}
