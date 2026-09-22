import Foundation
import LocalizationKit

/// `AppError` 프로토콜을 준수하는 범용 값 타입(Value Container) 에러 구조체.
///
/// SwiftUI `@Observable` 뷰모델, `.sheet(item:)`, `.alert(item:)` 과의 100% 호환을 위해 `Identifiable`을 채택하며,
/// 분산 원장 저장 및 네트워크 전송을 위해 `Codable`을 완벽하게 지원합니다.
///
/// Rust `anyhow` 스타일의 체이닝(`.context(...)`, `.withContext(key:value:)`)을 지원하여
/// 오류 발생 지점부터 처리 지점까지 맥락 정보를 계층적으로 누적할 수 있습니다.
public struct AnyAppError: AppError, Equatable, Hashable, Identifiable, Codable, Sendable {
    /// 고유 식별자 (SwiftUI `.sheet(item:)`, `.alert(item:)` 바인딩용).
    public let id: UUID

    /// 오류 식별 코드 (대문자 스네이크/점 표기, 예: "STORAGE.FILE_NOT_FOUND", "NETWORK.TIMEOUT").
    public let errorCode: String

    /// 오류 분류 범주.
    public let category: ErrorCategory

    /// 오류 심각도 수준.
    public let severity: ErrorSeverity

    /// 사용자 인터페이스(Alert/배너 등) 노출을 침묵 처리할지 여부 (예: Task 취소, 무해한 백그라운드 중단).
    public let isSilent: Bool

    /// 사용자 안내 문구 내 슬롯 치환 및 메타데이터 저장용 컨텍스트 맵.
    public let context: [String: String]

    /// 기저 원인 오류의 문자열 설명.
    ///
    /// 기저 오류(`underlyingError`)가 임의의 `Error`인 경우 `Codable` 및 `Equatable`을 보장할 수 없으므로,
    /// 원본 설명을 문자열로 캡처하여 안전하게 보존합니다.
    public let underlyingErrorDescription: String?

    /// `LocalizationKit` 다국어 리소스 키의 원시 문자열 값.
    public let rawL10nKey: String?

    // MARK: - AppError Protocol Conformance

    /// 기저 원인 오류 인스턴스 (Swift 6 strict concurrency 준수).
    ///
    /// `underlyingErrorDescription`이 존재하는 경우 `AnyUnderlyingError` 형태로 복원하여 제공합니다.
    public var underlyingError: (any Error & Sendable)? {
        guard let underlyingErrorDescription else { return nil }
        return AnyUnderlyingError(description: underlyingErrorDescription)
    }

    /// `LocalizationKit` 다국어 리소스 키 바인딩.
    ///
    /// `rawL10nKey`가 존재하는 경우 `AnyLocalizationKey` 형태로 제공합니다.
    public var l10nKey: (any LocalizationKey)? {
        guard let rawL10nKey else { return nil }
        return AnyLocalizationKey(rawValue: rawL10nKey)
    }

    // MARK: - Initializers

    /// 지정 초기화 구문.
    public init(
        id: UUID = UUID(),
        errorCode: String,
        category: ErrorCategory = .unknown,
        severity: ErrorSeverity = .error,
        isSilent: Bool = false,
        context: [String: String] = [:],
        underlyingErrorDescription: String? = nil,
        rawL10nKey: String? = nil
    ) {
        self.id = id
        self.errorCode = errorCode
        self.category = category
        self.severity = severity
        let isCancelled = (category == .cancelled) || (underlyingErrorDescription?.contains("CancellationError") == true)
        self.isSilent = isSilent || isCancelled
        self.context = context
        self.underlyingErrorDescription = underlyingErrorDescription
        self.rawL10nKey = rawL10nKey
    }

    /// 임의의 `AppError`를 감싸는 초기화 구문.
    public init(_ error: any AppError) {
        if let anyError = error as? AnyAppError {
            self.id = anyError.id
            self.errorCode = anyError.errorCode
            self.category = anyError.category
            self.severity = anyError.severity
            self.isSilent = anyError.isSilent
            self.context = anyError.context
            self.underlyingErrorDescription = anyError.underlyingErrorDescription
            self.rawL10nKey = anyError.rawL10nKey
        } else {
            self.id = UUID()
            self.errorCode = error.errorCode
            self.category = error.category
            self.severity = error.severity
            self.isSilent = error.isSilent
            self.context = error.context
            if let underlying = error.underlyingError {
                self.underlyingErrorDescription = Self.extractDescription(from: underlying)
            } else {
                self.underlyingErrorDescription = nil
            }
            self.rawL10nKey = error.l10nKey?.rawValue
        }
    }

    /// 기저 원인 오류(`any Error & Sendable`)를 포함하는 초기화 편의 구문.
    public init(
        id: UUID = UUID(),
        errorCode: String,
        category: ErrorCategory = .unknown,
        severity: ErrorSeverity = .error,
        isSilent: Bool = false,
        context: [String: String] = [:],
        underlyingError: any Error & Sendable,
        rawL10nKey: String? = nil
    ) {
        self.init(
            id: id,
            errorCode: errorCode,
            category: category,
            severity: severity,
            isSilent: isSilent,
            context: context,
            underlyingErrorDescription: Self.extractDescription(from: underlyingError),
            rawL10nKey: rawL10nKey
        )
    }

    /// `LocalizationKey`를 직접 전달받는 초기화 편의 구문.
    public init(
        id: UUID = UUID(),
        errorCode: String,
        category: ErrorCategory = .unknown,
        severity: ErrorSeverity = .error,
        isSilent: Bool = false,
        context: [String: String] = [:],
        underlyingErrorDescription: String? = nil,
        l10nKey: any LocalizationKey
    ) {
        self.init(
            id: id,
            errorCode: errorCode,
            category: category,
            severity: severity,
            isSilent: isSilent,
            context: context,
            underlyingErrorDescription: underlyingErrorDescription,
            rawL10nKey: l10nKey.rawValue
        )
    }

    /// 일반 `Error`를 포괄적으로 래핑하는 초기화 구문.
    public init(
        catchAll error: any Error & Sendable,
        category: ErrorCategory = .unknown,
        severity: ErrorSeverity = .error,
        isSilent: Bool = false
    ) {
        if let appError = error as? any AppError {
            self.init(appError)
        } else {
            self.init(
                errorCode: "UNKNOWN_ERROR",
                category: category,
                severity: severity,
                isSilent: isSilent,
                context: [:],
                underlyingErrorDescription: String(describing: error),
                rawL10nKey: nil
            )
        }
    }

    // MARK: - Rust-style Context Chaining

    /// Rust `anyhow` 스타일의 단일 컨텍스트 메시지 체이닝 메서드.
    ///
    /// 기존 컨텍스트에 이미 "context" 키가 존재하는 경우 `"{message}: {existing}"` 형태로 누적합니다.
    public func context(_ message: String) -> AnyAppError {
        var newContext = self.context
        if let existing = newContext["context"], !existing.isEmpty {
            newContext["context"] = "\(message): \(existing)"
        } else {
            newContext["context"] = message
        }
        return AnyAppError(
            id: self.id,
            errorCode: self.errorCode,
            category: self.category,
            severity: self.severity,
            isSilent: self.isSilent,
            context: newContext,
            underlyingErrorDescription: self.underlyingErrorDescription,
            rawL10nKey: self.rawL10nKey
        )
    }

    /// 특정 키와 값을 컨텍스트 맵에 추가/치환하는 체이닝 메서드.
    public func withContext(key: String, value: String) -> AnyAppError {
        var newContext = self.context
        newContext[key] = value
        return AnyAppError(
            id: self.id,
            errorCode: self.errorCode,
            category: self.category,
            severity: self.severity,
            isSilent: self.isSilent,
            context: newContext,
            underlyingErrorDescription: self.underlyingErrorDescription,
            rawL10nKey: self.rawL10nKey
        )
    }

    /// 여러 키-값 쌍을 일괄 추가하는 컨텍스트 체이닝 편의 메서드.
    public func withContext(_ additionalContext: [String: String]) -> AnyAppError {
        guard !additionalContext.isEmpty else { return self }
        var newContext = self.context
        for (key, value) in additionalContext {
            newContext[key] = value
        }
        return AnyAppError(
            id: self.id,
            errorCode: self.errorCode,
            category: self.category,
            severity: self.severity,
            isSilent: self.isSilent,
            context: newContext,
            underlyingErrorDescription: self.underlyingErrorDescription,
            rawL10nKey: self.rawL10nKey
        )
    }

    /// UI 알림 침묵 여부를 갱신하는 체이닝 메서드.
    public func withSilent(_ silent: Bool = true) -> AnyAppError {
        AnyAppError(
            id: self.id,
            errorCode: self.errorCode,
            category: self.category,
            severity: self.severity,
            isSilent: silent,
            context: self.context,
            underlyingErrorDescription: self.underlyingErrorDescription,
            rawL10nKey: self.rawL10nKey
        )
    }

    // MARK: - Equatable & Hashable

    /// 논리적 일치성 비교:
    ///
    /// UI 프레젠테이션용 임의 UUID인 `id`를 배제하고, `errorCode`, `category`, `severity`, `isSilent`,
    /// `context`, `underlyingErrorDescription`, `rawL10nKey`를 기준으로 비교합니다.
    public static func == (lhs: AnyAppError, rhs: AnyAppError) -> Bool {
        lhs.errorCode == rhs.errorCode &&
        lhs.category == rhs.category &&
        lhs.severity == rhs.severity &&
        lhs.isSilent == rhs.isSilent &&
        lhs.context == rhs.context &&
        lhs.underlyingErrorDescription == rhs.underlyingErrorDescription &&
        lhs.rawL10nKey == rhs.rawL10nKey
    }

    /// 해시 함수: `id`를 제외하고 내용 기반으로 해시를 생성합니다.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(errorCode)
        hasher.combine(category)
        hasher.combine(severity)
        hasher.combine(isSilent)
        hasher.combine(context)
        hasher.combine(underlyingErrorDescription)
        hasher.combine(rawL10nKey)
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case id
        case errorCode
        case category
        case severity
        case isSilent
        case context
        case underlyingErrorDescription
        case rawL10nKey
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.errorCode = try container.decode(String.self, forKey: .errorCode)
        self.category = try container.decodeIfPresent(ErrorCategory.self, forKey: .category) ?? .unknown
        self.severity = try container.decodeIfPresent(ErrorSeverity.self, forKey: .severity) ?? .error
        self.isSilent = try container.decodeIfPresent(Bool.self, forKey: .isSilent) ?? false
        self.context = try container.decodeIfPresent([String: String].self, forKey: .context) ?? [:]
        self.underlyingErrorDescription = try container.decodeIfPresent(String.self, forKey: .underlyingErrorDescription)
        self.rawL10nKey = try container.decodeIfPresent(String.self, forKey: .rawL10nKey)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(errorCode, forKey: .errorCode)
        try container.encode(category, forKey: .category)
        try container.encode(severity, forKey: .severity)
        try container.encode(isSilent, forKey: .isSilent)
        try container.encode(context, forKey: .context)
        try container.encodeIfPresent(underlyingErrorDescription, forKey: .underlyingErrorDescription)
        try container.encodeIfPresent(rawL10nKey, forKey: .rawL10nKey)
    }

    // MARK: - Internal Helpers

    private static func extractDescription(from error: any Error) -> String {
        if let appErr = error as? any AppError {
            return appErr.description
        }
        if let localized = error as? LocalizedError, let desc = localized.errorDescription, !desc.isEmpty {
            return desc
        }
        let describing = String(describing: error)
        guard describing.isEmpty else { return describing }
        return error.localizedDescription
    }
}

// MARK: - Supporting Types

/// 문자열 기반 기저 원인 오류 표현 래퍼.
public struct AnyUnderlyingError: LocalizedError, Sendable, CustomStringConvertible, Equatable, Hashable, Codable {
    public let description: String

    public init(description: String) {
        self.description = description
    }

    public var errorDescription: String? {
        description
    }
}

/// `LocalizationKey` 프로토콜을 준수하는 원시 문자열 래퍼.
public struct AnyLocalizationKey: LocalizationKey, Sendable, Equatable, Hashable, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

// MARK: - Extensions

extension AppError {
    /// 임의의 `AppError`를 `AnyAppError` 값 컨테이너로 지우기(erasure).
    public func eraseToAnyAppError() -> AnyAppError {
        AnyAppError(self)
    }
}

extension Error {
    /// 일반 `Error`를 `AnyAppError`로 변환.
    public func asAnyAppError(
        category: ErrorCategory = .unknown,
        severity: ErrorSeverity = .error,
        isSilent: Bool = false
    ) -> AnyAppError {
        let isCancelled = self is CancellationError
        let effectiveCategory = isCancelled ? .cancelled : category
        let effectiveSilent = isCancelled ? true : isSilent

        if let anyError = self as? AnyAppError {
            return effectiveSilent ? anyError.withSilent(true) : anyError
        }
        if let appError = self as? any AppError {
            let wrapped = AnyAppError(appError)
            return effectiveSilent ? wrapped.withSilent(true) : wrapped
        }
        return AnyAppError(
            errorCode: isCancelled ? "TASK_CANCELLED" : "UNKNOWN_ERROR",
            category: effectiveCategory,
            severity: effectiveSilent ? .info : severity,
            isSilent: effectiveSilent,
            context: [:],
            underlyingErrorDescription: String(describing: self),
            rawL10nKey: nil
        )
    }
}
