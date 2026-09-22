import Foundation
import LocalizationKit

/// 오류의 기술적/도메인적 분류 범주.
public enum ErrorCategory: String, Sendable, Codable, CaseIterable {
    case system
    case fileSystem
    case network
    case business
    case validation
    case permission
    case cancelled
    case unknown
}

/// 오류의 심각도 수준.
public enum ErrorSeverity: String, Sendable, Codable, CaseIterable, Comparable {
    case info
    case warning
    case error
    case critical

    private var priority: Int {
        switch self {
        case .info: return 0
        case .warning: return 1
        case .error: return 2
        case .critical: return 3
        }
    }

    public static func < (lhs: ErrorSeverity, rhs: ErrorSeverity) -> Bool {
        lhs.priority < rhs.priority
    }
}

/// 애플리케이션 공통 오류 프로토콜.
///
/// PAT (Protocol with Associated Types)를 사용하지 않아 `any AppError` existential로 자유롭게 보관 및 전달할 수 있습니다.
/// Swift 6 Concurrency 환경에서 완벽한 `Sendable` 무결성을 보장합니다.
public protocol AppError: LocalizedError, Sendable, CustomStringConvertible {
    /// 오류 식별 코드 (대문자 스네이크/점 표기, 예: "STORAGE.FILE_NOT_FOUND", "NETWORK.TIMEOUT").
    var errorCode: String { get }

    /// 오류 분류 범주.
    var category: ErrorCategory { get }

    /// 오류 심각도 수준.
    var severity: ErrorSeverity { get }

    /// 사용자 인터페이스(Alert/배너 등) 노출을 침묵 처리할지 여부 (예: Task 취소, 무해한 백그라운드 중단).
    var isSilent: Bool { get }

    /// 기저 원인 오류 (Swift 6 strict concurrency 호환).
    var underlyingError: (any Error & Sendable)? { get }

    /// 사용자 안내 문구 내 슬롯 치환용 맵 (예: ["path": "/tmp/a"]).
    var context: [String: String] { get }

    /// `LocalizationKit` 다국어 리소스 키 바인딩.
    var l10nKey: (any LocalizationKey)? { get }

    /// 사용자 노출용 로컬라이즈 메시지를 반환합니다.
    func userFacingMessage(using manager: LocalizationManager?) -> String

    /// 사용자 노출용 복구 제안 문구를 반환합니다.
    func userFacingRecoverySuggestion(using manager: LocalizationManager?) -> String?
}

// MARK: - Default Implementation

extension AppError {
    public var isSilent: Bool {
        if category == .cancelled {
            return true
        }
        if underlyingError is CancellationError {
            return true
        }
        return false
    }

    public var underlyingError: (any Error & Sendable)? {
        nil
    }

    public var context: [String: String] {
        [:]
    }

    public var l10nKey: (any LocalizationKey)? {
        nil
    }

    public var userFacingMessage: String {
        userFacingMessage(using: nil)
    }

    public var userFacingRecoverySuggestion: String? {
        userFacingRecoverySuggestion(using: nil)
    }

    public var errorDescription: String? {
        userFacingMessage
    }

    public var recoverySuggestion: String? {
        userFacingRecoverySuggestion
    }

    public var failureReason: String? {
        errorCode
    }

    public var description: String {
        "[\(errorCode)] \(userFacingMessage)"
    }

    public func userFacingMessage(using manager: LocalizationManager? = nil) -> String {
        let base: String
        if let key = l10nKey {
            base = resolveL10nString(key.rawValue, using: manager)
        } else if let underlying = underlyingError {
            base = underlying.localizedDescription
        } else {
            base = errorCode
        }

        return AppErrorLocalization.substituteSlots(into: base, context: context)
    }

    public func userFacingRecoverySuggestion(using manager: LocalizationManager? = nil) -> String? {
        if let suggestion = resolveL10nRecovery(using: manager) {
            return AppErrorLocalization.substituteSlots(into: suggestion, context: context)
        }

        guard let underlying = underlyingError as? LocalizedError,
              let suggestion = underlying.recoverySuggestion else {
            return nil
        }
        return AppErrorLocalization.substituteSlots(into: suggestion, context: context)
    }

    private func resolveL10nString(_ rawKey: String, using manager: LocalizationManager?) -> String {
        guard let manager else {
            return CLILocalization.string(rawKey)
        }
        guard Thread.isMainThread else {
            return CLILocalization.string(rawKey)
        }
        return MainActor.assumeIsolated {
            manager.string(rawKey)
        }
    }

    private func resolveL10nRecovery(using manager: LocalizationManager?) -> String? {
        guard let key = l10nKey else { return nil }
        let recoveryRawKey = "\(key.rawValue).recovery"
        let translated = resolveL10nString(recoveryRawKey, using: manager)
        guard translated != recoveryRawKey else { return nil }
        return translated
    }
}
