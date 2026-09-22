import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// 테스트 환경변수를 안전하게 격리 및 조작하기 위한 유틸리티.
///
/// 주어진 블록(`withTestEnvironment`) 내에서만 환경변수를 재정의하고,
/// 블록이 정상 종료되거나 에러가 발생해도 기존의 환경변수 상태로 완벽히 복원합니다.
public enum TestEnvironment {
    private static let lock = NSLock()

    private actor AsyncCoordinator {
        static let shared = AsyncCoordinator()

        func run<T: Sendable>(
            _ overrides: [String: String?],
            _ body: @Sendable () async throws -> T
        ) async rethrows -> T {
            let originalValues = TestEnvironment.snapshotAndApply(overrides: overrides)
            defer {
                TestEnvironment.restore(originalValues: originalValues)
            }
            return try await body()
        }
    }

    /// 지정된 환경변수 맵을 적용한 상태로 스코프 클로저를 실행하고, 완료 후 이전 상태로 복원합니다.
    ///
    /// - Parameters:
    ///   - overrides: 설정할 환경변수 딕셔너리. 값이 `nil`인 경우 해당 환경변수를 임시 제거(unset)합니다.
    ///   - body: 환경변수가 오버라이드된 상태에서 실행할 동기 클로저.
    /// - Returns: 클로저의 반환값.
    @discardableResult
    public static func withTestEnvironment<T>(
        _ overrides: [String: String?],
        _ body: () throws -> T
    ) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }

        let originalValues = snapshotAndApply(overrides: overrides)
        defer {
            restore(originalValues: originalValues)
        }

        return try body()
    }

    /// 지정된 환경변수 맵을 적용한 상태로 비동기 스코프 클로저를 실행하고, 완료 후 이전 상태로 복원합니다.
    ///
    /// - Parameters:
    ///   - overrides: 설정할 환경변수 딕셔너리. 값이 `nil`인 경우 해당 환경변수를 임시 제거(unset)합니다.
    ///   - body: 환경변수가 오버라이드된 상태에서 실행할 비동기 클로저.
    /// - Returns: 클로저의 반환값.
    @discardableResult
    public static func withTestEnvironment<T: Sendable>(
        _ overrides: [String: String?],
        _ body: @Sendable () async throws -> T
    ) async rethrows -> T {
        try await AsyncCoordinator.shared.run(overrides, body)
    }

    /// 단일 환경변수를 적용한 상태로 스코프 클로저를 실행하고 복원합니다.
    @discardableResult
    public static func withEnvironmentVariable<T>(
        key: String,
        value: String?,
        _ body: () throws -> T
    ) rethrows -> T {
        try withTestEnvironment([key: value], body)
    }

    /// 단일 환경변수를 적용한 상태로 비동기 스코프 클로저를 실행하고 복원합니다.
    @discardableResult
    public static func withEnvironmentVariable<T: Sendable>(
        key: String,
        value: String?,
        _ body: @Sendable () async throws -> T
    ) async rethrows -> T {
        try await withTestEnvironment([key: value], body)
    }

    // MARK: - Private Helpers

    /// 현재 환경변수 상태를 백업하고 오버라이드를 적용합니다.
    private static func snapshotAndApply(overrides: [String: String?]) -> [String: String?] {
        var originalValues: [String: String?] = [:]

        for (key, newValue) in overrides {
            if let currentCStr = getenv(key) {
                originalValues[key] = String(cString: currentCStr)
            } else {
                originalValues[key] = nil
            }

            if let newValue = newValue {
                setenv(key, newValue, 1)
            } else {
                unsetenv(key)
            }
        }

        return originalValues
    }

    /// 백업해 둔 원래 환경변수 상태로 복원합니다.
    private static func restore(originalValues: [String: String?]) {
        for (key, originalValue) in originalValues {
            if let originalValue = originalValue {
                setenv(key, originalValue, 1)
            } else {
                unsetenv(key)
            }
        }
    }
}
