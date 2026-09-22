import XCTest
@testable import TestingAdapterKit

final class AsyncPollingMatcherTests: XCTestCase {

    // MARK: - Immediate & Asynchronous Success Tests

    func testExpectEventuallyImmediateSuccess() async throws {
        let startTime = Date()
        let result = try await expectEventually(timeout: 1.0, pollInterval: 0.01) {
            true
        }
        let elapsed = Date().timeIntervalSince(startTime)

        XCTAssertTrue(result)
        XCTAssertLessThan(elapsed, 0.5, "즉시 성공하는 조건은 첫 번째 평가에서 지연 없이 완료되어야 합니다.")
    }

    func testExpectEventuallyAsyncSuccess() async throws {
        let counter = Counter()
        Task {
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms 후 증분
            await counter.increment()
        }

        let result = try await expectEventually(timeout: 2.0, pollInterval: 0.02) {
            let val = await counter.value
            return val > 0
        }

        XCTAssertTrue(result)
        let finalVal = await counter.value
        XCTAssertEqual(finalVal, 1)
    }

    // MARK: - Timeout & Diagnostic Error Tests

    func testExpectEventuallyTimeoutThrowsPollingTimeoutError() async throws {
        do {
            try await expectEventually(
                timeout: 0.1,
                pollInterval: 0.02,
                message: "Counter never reaches 999"
            ) {
                false
            }
            XCTFail("타임아웃 시 PollingTimeoutError가 발생해야 합니다.")
        } catch let error as PollingTimeoutError {
            XCTAssertEqual(error.timeout, 0.1)
            XCTAssertGreaterThanOrEqual(error.attempts, 1)
            XCTAssertTrue(error.description.contains("Counter never reaches 999"))
            XCTAssertTrue(error.description.contains("Polling condition failed"))
        } catch {
            XCTFail("예상치 못한 에러 발생: \(error)")
        }
    }

    func testExpectEventuallySuppressesTransientErrorsUntilSuccess() async throws {
        let flaky = FlakyResource()

        let result = try await expectEventually(timeout: 1.5, pollInterval: 0.02) {
            try await flaky.fetchOrThrow()
        }

        XCTAssertTrue(result)
        let attempts = await flaky.attemptCount
        XCTAssertGreaterThanOrEqual(attempts, 3, "일시적 에러를 견디며 재시도해야 합니다.")
    }

    func testExpectEventuallyCapturesLastErrorOnTimeout() async throws {
        do {
            try await expectEventually(timeout: 0.1, pollInterval: 0.02) {
                throw TestCustomError.simulatedFailure
            }
            XCTFail("타임아웃 시 에러가 던져져야 합니다.")
        } catch let error as PollingTimeoutError {
            guard let last = error.lastError as? TestCustomError else {
                XCTFail("마지막 내부 에러가 기록되어야 합니다. Got: \(String(describing: error.lastError))")
                return
            }
            XCTAssertEqual(last, .simulatedFailure)
        } catch {
            XCTFail("예상치 못한 에러: \(error)")
        }
    }

    // MARK: - Value Polling Tests

    func testExpectEventuallyValueSuccess() async throws {
        let holder = ValueHolder<String>()
        Task {
            try? await Task.sleep(nanoseconds: 40_000_000)
            await holder.set("ready")
        }

        let value = try await expectEventuallyValue(
            timeout: 1.0,
            pollInterval: 0.02,
            supplier: {
                await holder.get()
            },
            condition: { $0 == "ready" }
        )

        XCTAssertEqual(value, "ready")
    }

    func testExpectEventuallyValueTimeout() async throws {
        do {
            _ = try await expectEventuallyValue(
                timeout: 0.1,
                pollInterval: 0.02,
                message: "Value never supplied",
                supplier: {
                    nil as Int?
                }
            )
            XCTFail("타임아웃 에러가 발생해야 합니다.")
        } catch let error as PollingTimeoutError {
            XCTAssertTrue(error.description.contains("Value never supplied"))
        }
    }

    // MARK: - Negative Assertion (expectNever) Tests

    func testExpectNeverSuccess() async throws {
        let flag = FlagHolder()
        let result = try await AsyncPollingMatcher.expectNever(
            duration: 0.1,
            pollInterval: 0.02
        ) {
            await flag.isRaised
        }
        XCTAssertTrue(result)
    }

    func testExpectNeverFailure() async throws {
        let flag = FlagHolder()
        Task {
            try? await Task.sleep(nanoseconds: 30_000_000)
            await flag.raise()
        }

        do {
            _ = try await AsyncPollingMatcher.expectNever(
                duration: 0.2,
                pollInterval: 0.02
            ) {
                await flag.isRaised
            }
            XCTFail("조건이 참이 되면 expectNever는 실패해야 합니다.")
        } catch let error as PollingTimeoutError {
            XCTAssertTrue(error.description.contains("Condition was expected to never become true"))
        }
    }
}

// MARK: - Test Helpers

private actor Counter {
    var value: Int = 0
    func increment() {
        value += 1
    }
}

private actor FlakyResource {
    var attemptCount: Int = 0
    func fetchOrThrow() throws -> Bool {
        attemptCount += 1
        if attemptCount < 3 {
            throw TestCustomError.transientNetworkError
        }
        return true
    }
}

private actor ValueHolder<T: Sendable> {
    var value: T?
    func set(_ newValue: T) {
        value = newValue
    }
    func get() -> T? {
        value
    }
}

private actor FlagHolder {
    var isRaised: Bool = false
    func raise() {
        isRaised = true
    }
}

private enum TestCustomError: Error, Equatable {
    case simulatedFailure
    case transientNetworkError
}
