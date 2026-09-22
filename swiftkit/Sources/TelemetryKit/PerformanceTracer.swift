import Foundation

/// Sentry 제거 후 no-op 스텁. 함수를 그대로 실행하되 트레이싱하지 않는다.
public enum PerformanceTracer {
    public static func trace<T>(
        _ name: String,
        operation: String = "function",
        _ body: () throws -> T
    ) rethrows -> T {
        try body()
    }

    public static func trace<T>(
        _ name: String,
        operation: String = "function",
        _ body: () async throws -> T
    ) async rethrows -> T {
        try await body()
    }
}
