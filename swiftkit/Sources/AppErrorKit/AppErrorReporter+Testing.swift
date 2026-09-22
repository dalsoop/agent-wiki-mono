import Foundation

extension AppErrorReporter {

    // MARK: - Testing Environment Detection

    /// 현재 프로세스가 테스트 러너(XCTest 또는 Swift Testing) 환경에서 동작 중인지 감지합니다.
    public static var isTesting: Bool {
        let env = ProcessInfo.processInfo.environment
        let testEnvKeys = [
            "XCTestConfigurationFilePath",
            "XCTestSessionIdentifier",
            "XCTestBundlePath",
            "SWIFT_TESTING_ENABLED",
            "TEST_RUNNER_PID"
        ]
        if testEnvKeys.contains(where: { env[$0] != nil }) {
            return true
        }
        if ProcessInfo.processInfo.arguments.contains("-XCTest") {
            return true
        }
        if NSClassFromString("XCTestCase") != nil {
            return true
        }
        return false
    }

    // MARK: - Scoped Execution (Point-Free Style)

    /// 특정 코드 블록 실행 동안만 적용될 에러 핸들러를 바인딩합니다.
    @discardableResult
    public static func withHandler<R>(
        _ handler: @escaping ErrorHandler,
        operation: () throws -> R
    ) rethrows -> R {
        try $currentHandler.withValue(handler) {
            try operation()
        }
    }

    /// 비동기 특정 코드 블록 실행 동안만 적용될 에러 핸들러를 바인딩합니다.
    @discardableResult
    public static func withHandler<R>(
        _ handler: @escaping ErrorHandler,
        operation: () async throws -> R
    ) async rethrows -> R {
        try await $currentHandler.withValue(handler) {
            try await operation()
        }
    }

    /// 테스트 환경에서 의도된 오류가 보고될 것으로 예상되는 코드 블록을 실행합니다.
    ///
    /// 블록 내에서 보고된 `AppError`는 테스트 실패를 유발하지 않습니다.
    @discardableResult
    public static func withExpectedError<R>(
        handler: ErrorHandler? = nil,
        operation: () throws -> R
    ) rethrows -> R {
        try $isExpected.withValue(true) {
            if let handler {
                try $currentHandler.withValue(handler) {
                    try operation()
                }
            } else {
                try operation()
            }
        }
    }

    /// 비동기 테스트 환경에서 의도된 오류가 보고될 것으로 예상되는 코드 블록을 실행합니다.
    @discardableResult
    public static func withExpectedError<R>(
        handler: ErrorHandler? = nil,
        operation: () async throws -> R
    ) async rethrows -> R {
        try await $isExpected.withValue(true) {
            if let handler {
                try await $currentHandler.withValue(handler) {
                    try await operation()
                }
            } else {
                try await operation()
            }
        }
    }

    /// 코드 블록 실행 중 보고된 모든 기대된 오류를 캡처하여 배열로 반환합니다.
    public static func captureExpectedErrors<R>(
        operation: () throws -> R
    ) rethrows -> (result: R, errors: [AnyAppError]) {
        let collector = ErrorCollector()
        let result = try withExpectedError(handler: { error, _, _ in
            collector.append(error)
        }) {
            try operation()
        }
        return (result, collector.errors)
    }

    /// 비동기 코드 블록 실행 중 보고된 모든 기대된 오류를 캡처하여 배열로 반환합니다.
    public static func captureExpectedErrors<R>(
        operation: () async throws -> R
    ) async rethrows -> (result: R, errors: [AnyAppError]) {
        let collector = ErrorCollector()
        let result = try await withExpectedError(handler: { error, _, _ in
            collector.append(error)
        }) {
            try await operation()
        }
        return (result, collector.errors)
    }

    // MARK: - Test Failure Recording

    func recordTestFailure(for error: AnyAppError, file: StaticString, line: UInt) {
        let failureMessage = formatTestFailureMessage(for: error, file: file, line: line)


        fputs("\(file):\(line): error: \(failureMessage)\n", stderr)
    }

    /// 테스트 실패 메시지를 가독성 높게 포맷팅합니다.
    public func formatTestFailureMessage(for error: AnyAppError, file: StaticString, line: UInt) -> String {
        var lines: [String] = [
            "An unexpected AppError was reported:",
            "  Code:     [\(error.errorCode)]",
            "  Severity: \(error.severity.rawValue.uppercased())",
            "  Category: \(error.category.rawValue)",
            "  Message:  \(error.userFacingMessage)"
        ]
        appendFailureDetails(to: &lines, for: error)
        lines.append("  Source:   \(file):\(line)")
        return lines.joined(separator: "\n")
    }

    private func appendFailureDetails(to lines: inout [String], for error: AnyAppError) {
        if let recovery = error.userFacingRecoverySuggestion {
            lines.append("  Recovery: \(recovery)")
        }
        if let underlying = error.underlyingErrorDescription {
            lines.append("  Cause:    \(underlying)")
        }
        guard !error.context.isEmpty else { return }
        let contextPairs = error.context.sorted(by: { $0.key < $1.key })
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ", ")
        lines.append("  Context:  {\(contextPairs)}")
    }
}
