import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// 비동기 폴링 대기 중 타임아웃이 발생했을 때 던져지는 에러.
public struct PollingTimeoutError: Error, CustomStringConvertible, LocalizedError, Sendable {
    /// 설정된 최대 대기 시간 (초)
    public let timeout: TimeInterval
    /// 폴링 주기 (초)
    public let pollInterval: TimeInterval
    /// 실제 경과된 시간 (초)
    public let elapsed: TimeInterval
    /// 시도한 총 횟수
    public let attempts: Int
    /// 폴링 중 마지막으로 발생한 내부 에러 (있을 경우)
    public let lastError: (any Error)?
    /// 호출자가 지정한 추가 진단 메시지
    public let customMessage: String?

    public init(
        timeout: TimeInterval,
        pollInterval: TimeInterval,
        elapsed: TimeInterval,
        attempts: Int,
        lastError: (any Error)? = nil,
        message: String? = nil
    ) {
        self.timeout = timeout
        self.pollInterval = pollInterval
        self.elapsed = elapsed
        self.attempts = attempts
        self.lastError = lastError
        self.customMessage = message
    }

    public var description: String {
        var desc = "Polling condition failed within \(String(format: "%.3f", timeout))s (elapsed: \(String(format: "%.3f", elapsed))s across \(attempts) attempts, pollInterval: \(String(format: "%.3f", pollInterval))s)"
        if let customMessage = customMessage, !customMessage.isEmpty {
            desc += " - \(customMessage)"
        }
        if let lastError = lastError {
            desc += " [last error: \(lastError)]"
        }
        return desc
    }

    public var errorDescription: String? {
        description
    }
}

/// 테스트에서 임의의 `Thread.sleep` 또는 단순 `Task.sleep`을 대체하는 비동기 폴링 매처.
///
/// 조건이 참(`true`)이 되는 즉시 조기 반환(Early Return)하여 테스트 실행 시간을 단축하고,
/// 타임아웃 초과 시 상세한 진단 정보가 담긴 `PollingTimeoutError`를 발생시킵니다.
public enum AsyncPollingMatcher {
    /// 지정된 조건이 참이 될 때까지 주기적으로 폴링하며 비동기 대기합니다.
    ///
    /// - Parameters:
    ///   - timeout: 최대 대기 시간(초). 기본값: `3.0`초
    ///   - pollInterval: 재시도 간격(초). 기본값: `0.05`초 (50ms)
    ///   - message: 타임아웃 실패 시 출력할 사용자 정의 메시지 (선택)
    ///   - condition: 만족 여부를 검사하는 비동기 클로저. 클로저가 `true`를 반환하면 즉시 대기를 종료하고 성공합니다.
    ///                클로저 내부에서 에러가 발생하면 마지막 에러로 기록되고 타임아웃까지 재시도합니다.
    /// - Returns: 조건 충족 시 `true`를 반환합니다.
    /// - Throws: 타임아웃 초과 시 `PollingTimeoutError`를 발생시킵니다.
    @discardableResult
    public static func expectEventually(
        timeout: TimeInterval = 3.0,
        pollInterval: TimeInterval = 0.05,
        message: String? = nil,
        condition: @Sendable () async throws -> Bool
    ) async throws -> Bool {
        let clock = ContinuousClock()
        let startTime = clock.now
        let timeoutNanos = Int64(max(0.001, timeout) * 1_000_000_000)
        let intervalNanos = UInt64(max(0.001, pollInterval) * 1_000_000_000)
        let deadline = startTime + .nanoseconds(timeoutNanos)

        var attempts = 0
        var lastCapturedError: (any Error)? = nil

        while clock.now < deadline {
            try Task.checkCancellation()
            attempts += 1

            do {
                if try await condition() {
                    return true
                }
            } catch {
                lastCapturedError = error
            }

            if clock.now >= deadline {
                break
            }

            try await Task.sleep(nanoseconds: intervalNanos)
        }

        // 데드라인 직후 마지막 1회 최종 확인
        try Task.checkCancellation()
        attempts += 1
        do {
            if try await condition() {
                return true
            }
        } catch {
            lastCapturedError = error
        }

        let totalDuration = startTime.duration(to: clock.now)
        let elapsedSeconds = Double(totalDuration.components.seconds) +
            Double(totalDuration.components.attoseconds) / 1e18

        throw PollingTimeoutError(
            timeout: timeout,
            pollInterval: pollInterval,
            elapsed: elapsedSeconds,
            attempts: attempts,
            lastError: lastCapturedError,
            message: message
        )
    }

    /// 공급자(`supplier`)가 `nil`이 아닌 유효한 값을 반환하고 추가 조건(`condition`)을 만족할 때까지 폴링합니다.
    ///
    /// - Parameters:
    ///   - timeout: 최대 대기 시간(초). 기본값: `3.0`초
    ///   - pollInterval: 재시도 간격(초). 기본값: `0.05`초
    ///   - message: 타임아웃 실패 시 출력할 사용자 정의 메시지 (선택)
    ///   - supplier: 값을 생성 또는 조회하는 비동기 클로저
    ///   - condition: 추출된 값의 추가 만족 조건 (기본값: 항상 참)
    /// - Returns: 조건을 만족한 최종 값
    @discardableResult
    public static func expectEventuallyValue<T: Sendable>(
        timeout: TimeInterval = 3.0,
        pollInterval: TimeInterval = 0.05,
        message: String? = nil,
        supplier: @Sendable () async throws -> T?,
        condition: @Sendable (T) throws -> Bool = { _ in true }
    ) async throws -> T {
        let clock = ContinuousClock()
        let startTime = clock.now
        let timeoutNanos = Int64(max(0.001, timeout) * 1_000_000_000)
        let intervalNanos = UInt64(max(0.001, pollInterval) * 1_000_000_000)
        let deadline = startTime + .nanoseconds(timeoutNanos)

        var attempts = 0
        var lastCapturedError: (any Error)? = nil
        var lastCapturedValue: T? = nil

        while clock.now < deadline {
            try Task.checkCancellation()
            attempts += 1

            do {
                if let value = try await supplier() {
                    lastCapturedValue = value
                    if try condition(value) {
                        return value
                    }
                }
            } catch {
                lastCapturedError = error
            }

            if clock.now >= deadline {
                break
            }

            try await Task.sleep(nanoseconds: intervalNanos)
        }

        // 데드라인 직후 마지막 1회 최종 확인
        try Task.checkCancellation()
        attempts += 1
        do {
            if let value = try await supplier() {
                lastCapturedValue = value
                if try condition(value) {
                    return value
                }
            }
        } catch {
            lastCapturedError = error
        }

        let totalDuration = startTime.duration(to: clock.now)
        let elapsedSeconds = Double(totalDuration.components.seconds) +
            Double(totalDuration.components.attoseconds) / 1e18

        var failureMessage = message ?? "Supplier condition not satisfied"
        if let lastValue = lastCapturedValue {
            failureMessage += " (last value: \(lastValue))"
        }

        throw PollingTimeoutError(
            timeout: timeout,
            pollInterval: pollInterval,
            elapsed: elapsedSeconds,
            attempts: attempts,
            lastError: lastCapturedError,
            message: failureMessage
        )
    }

    /// 지정된 기간 동안 조건이 참이 되지 않음을 보장(검증)합니다.
    ///
    /// 만약 기간 내에 조건이 한 번이라도 `true`가 되면 즉시 에러를 발생시킵니다.
    @discardableResult
    public static func expectNever(
        duration: TimeInterval = 0.5,
        pollInterval: TimeInterval = 0.05,
        message: String? = nil,
        condition: @Sendable () async throws -> Bool
    ) async throws -> Bool {
        let clock = ContinuousClock()
        let startTime = clock.now
        let durationNanos = Int64(max(0.001, duration) * 1_000_000_000)
        let intervalNanos = UInt64(max(0.001, pollInterval) * 1_000_000_000)
        let deadline = startTime + .nanoseconds(durationNanos)

        while clock.now < deadline {
            try Task.checkCancellation()
            if try await condition() {
                let msg = message ?? "Condition was expected to never become true, but succeeded unexpectedly."
                throw PollingTimeoutError(
                    timeout: duration,
                    pollInterval: pollInterval,
                    elapsed: 0,
                    attempts: 1,
                    message: msg
                )
            }
            try await Task.sleep(nanoseconds: intervalNanos)
        }

        return true
    }
}

// MARK: - Global Convenience Functions

/// 지정된 조건이 참(`true`)이 될 때까지 주기적으로 폴링하며 비동기 대기합니다.
///
/// 테스트 코드에서 `try await expectEventually { ... }` 형태로 간결하게 호출할 수 있습니다.
@discardableResult
public func expectEventually(
    timeout: TimeInterval = 3.0,
    pollInterval: TimeInterval = 0.05,
    message: String? = nil,
    condition: @Sendable () async throws -> Bool
) async throws -> Bool {
    try await AsyncPollingMatcher.expectEventually(
        timeout: timeout,
        pollInterval: pollInterval,
        message: message,
        condition: condition
    )
}

/// 공급자(`supplier`)가 유효한 값을 반환하고 조건을 충족할 때까지 폴링합니다.
@discardableResult
public func expectEventuallyValue<T: Sendable>(
    timeout: TimeInterval = 3.0,
    pollInterval: TimeInterval = 0.05,
    message: String? = nil,
    supplier: @Sendable () async throws -> T?,
    condition: @Sendable (T) throws -> Bool = { _ in true }
) async throws -> T {
    try await AsyncPollingMatcher.expectEventuallyValue(
        timeout: timeout,
        pollInterval: pollInterval,
        message: message,
        supplier: supplier,
        condition: condition
    )
}
