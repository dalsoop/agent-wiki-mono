import Foundation
import LocalizationKit

/// CLI 및 애플리케이션 공통 입력 및 옵션 유효성 검증 오류.
///
/// POSIX `sysexits.h`의 `EX_USAGE` (64) 및 RFC 9457 Problem Details 규약과 100% 호환됩니다.
public struct AppValidationError: AppError, Equatable, Sendable, Codable {
    public let errorCode: String
    public let message: String
    public let recoverySuggestion: String?
    public let context: [String: String]

    public var category: ErrorCategory { .validation }
    public var severity: ErrorSeverity { .warning }

    public init(
        errorCode: String = "VALIDATION.ERROR",
        message: String,
        recoverySuggestion: String? = nil,
        context: [String: String] = [:]
    ) {
        self.errorCode = errorCode
        self.message = message
        self.recoverySuggestion = recoverySuggestion
        self.context = context
    }

    public func userFacingMessage(using manager: LocalizationManager? = nil) -> String {
        message
    }

    public func userFacingRecoverySuggestion(using manager: LocalizationManager? = nil) -> String? {
        recoverySuggestion
    }
}
