import Foundation
import LocalizationKit

/// `AppErrorKit`과 `LocalizationKit` 간의 다국어(i18n) 연동 엔진.
///
/// GUI(`LocalizationManager`), CLI/Core(`CLILocalization`) 환경별 에러 메시지 및
/// 복구 제안(`recoverySuggestion`) 렌더링을 일관되게 제공합니다.
/// Localizable.strings 내의 `%{key}` 및 `%@` 슬롯 치환 시 `CLILocalization.substituteSlots`를
/// 활용하여 C 포맷 인자 불일치 크래시(SIGSEGV)를 원천 차단하고 안전한 문자열 대치를 보장합니다.
public enum AppErrorLocalization {

    // MARK: - CLI Configuration Options

    /// CLI 렌더링 설정 옵션.
    public struct CLIOptions {
        public var defaultsKey: String
        public var userDefaults: UserDefaults
        public var base: Bundle

        public init(
            defaultsKey: String = "app.language",
            userDefaults: UserDefaults = .standard,
            base: Bundle = ResourceBundle.localization()
        ) {
            self.defaultsKey = defaultsKey
            self.userDefaults = userDefaults
            self.base = base
        }
    }

    // MARK: - Slot Substitution

    /// Localizable.strings 문구 내의 `%{key}`(또는 `{key}`) 및 `%@`(위치 지정자) 슬롯을 context 및 positionalValues로 안전하게 치환합니다.
    ///
    /// C-포맷 지정자(`%@`, `%1$@`, `%d` 등)는 `CLILocalization.substituteSlots`를 거치므로
    /// CVarArg 타입 불일치 크래시(SIGSEGV) 없이 안전하게 치환됩니다.
    ///
    /// - Parameters:
    ///   - format: 치환 대상 템플릿 문자열.
    ///   - context: `%{key}` 슬롯에 매핑할 키-값 딕셔너리.
    ///   - positionalValues: `%@` 슬롯에 매핑할 위치 기반 값 배열 (Sendable 준수).
    /// - Returns: 모든 슬롯이 안전하게 치환된 최종 문자열.
    public static func substituteSlots(
        into format: String,
        context: [String: String] = [:],
        positionalValues: [any CustomStringConvertible & Sendable] = []
    ) -> String {
        guard !format.isEmpty else { return format }

        // 1. %% 리터럴 보호
        let placeholder = "\u{E000}"
        var work = format.replacingOccurrences(of: "%%", with: placeholder)

        // 2. %{key} 및 {key} 슬롯 치환
        if !context.isEmpty {
            work = replaceNamedSlots(in: work, pattern: #"%\{([a-zA-Z0-9_.-]+)\}"#, context: context)
            work = replaceNamedSlots(in: work, pattern: #"\{([a-zA-Z0-9_.-]+)\}"#, context: context)
        }

        // 3. Positional slot (%@, %1$@, %d 등) 치환 (CLILocalization.substituteSlots 활용)
        work = substitutePositional(in: work, context: context, positionalValues: positionalValues)

        // 4. %% 복원
        return work.replacingOccurrences(of: placeholder, with: "%")
    }

    /// `[String: any Sendable]` 타입의 context를 지원하는 오버로드.
    public static func substituteSlots(
        into format: String,
        context: [String: any Sendable],
        positionalValues: [any CustomStringConvertible & Sendable] = []
    ) -> String {
        let stringContext = context.mapValues { String(describing: $0) }
        return substituteSlots(into: format, context: stringContext, positionalValues: positionalValues)
    }

    // MARK: - GUI Rendering (LocalizationManager)

    /// GUI 환경에서 `LocalizationManager`를 통해 현재 런타임 언어(KR/EN)로 에러 메시지를 렌더링합니다.
    ///
    /// `l10nKey`에 해당하는 번역이 없을 경우, 안전하게 영문/기술 기본 메시지 또는 `errorCode`로 폴백합니다.
    @MainActor
    public static func renderGUIMessage(
        for error: any AppError,
        using manager: LocalizationManager,
        positionalValues: [any CustomStringConvertible & Sendable] = []
    ) -> String {
        renderGUIMessage(
            errorCode: error.errorCode,
            l10nKey: error.l10nKey,
            underlyingError: error.underlyingError,
            context: error.context,
            positionalValues: positionalValues,
            using: manager
        )
    }

    /// GUI 환경에서 `LocalizationManager`를 통해 현재 런타임 언어(KR/EN)로 복구 제안(`recoverySuggestion`)을 렌더링합니다.
    @MainActor
    public static func renderGUIRecoverySuggestion(
        for error: any AppError,
        using manager: LocalizationManager,
        positionalValues: [any CustomStringConvertible & Sendable] = []
    ) -> String? {
        renderGUIRecoverySuggestion(
            l10nKey: error.l10nKey,
            underlyingError: error.underlyingError,
            context: error.context,
            positionalValues: positionalValues,
            using: manager
        )
    }

    /// GUI 환경 컴포넌트 단위 에러 메시지 렌더링.
    @MainActor
    public static func renderGUIMessage(
        errorCode: String,
        l10nKey: (any LocalizationKey)?,
        defaultMessage: String? = nil,
        underlyingError: (any Error)? = nil,
        context: [String: String] = [:],
        positionalValues: [any CustomStringConvertible & Sendable] = [],
        using manager: LocalizationManager
    ) -> String {
        if let template = resolveGUITemplate(l10nKey: l10nKey, using: manager) {
            return substituteSlots(into: template, context: context, positionalValues: positionalValues)
        }
        let fallback = resolveFallbackTemplate(defaultMessage: defaultMessage, underlyingError: underlyingError, errorCode: errorCode)
        return substituteSlots(into: fallback, context: context, positionalValues: positionalValues)
    }

    /// GUI 환경 컴포넌트 단위 복구 제안 렌더링.
    @MainActor
    public static func renderGUIRecoverySuggestion(
        l10nKey: (any LocalizationKey)?,
        defaultSuggestion: String? = nil,
        underlyingError: (any Error)? = nil,
        context: [String: String] = [:],
        positionalValues: [any CustomStringConvertible & Sendable] = [],
        using manager: LocalizationManager
    ) -> String? {
        if let template = resolveGUIRecoveryTemplate(l10nKey: l10nKey, using: manager) {
            return substituteSlots(into: template, context: context, positionalValues: positionalValues)
        }
        guard let fallback = resolveFallbackRecovery(defaultSuggestion: defaultSuggestion, underlyingError: underlyingError) else {
            return nil
        }
        return substituteSlots(into: fallback, context: context, positionalValues: positionalValues)
    }

    // MARK: - CLI / Core Rendering (CLILocalization)

    /// CLI/Core 환경에서 `CLILocalization.string`을 통해 정적 언어 설정으로 에러 메시지를 렌더링합니다.
    ///
    /// `@MainActor`에 격리되지 않아 비동기/동기 Core 및 CLI 어디서나 안전하게 호출 가능합니다.
    public static func renderCLIMessage(
        for error: any AppError,
        positionalValues: [any CustomStringConvertible & Sendable] = [],
        defaultsKey: String = "app.language",
        userDefaults: UserDefaults = .standard,
        base: Bundle = ResourceBundle.localization()
    ) -> String {
        renderCLIMessage(
            errorCode: error.errorCode,
            l10nKey: error.l10nKey,
            underlyingError: error.underlyingError,
            context: error.context,
            positionalValues: positionalValues,
            options: CLIOptions(defaultsKey: defaultsKey, userDefaults: userDefaults, base: base)
        )
    }

    /// CLI/Core 환경에서 `CLILocalization.string`을 통해 정적 언어 설정으로 복구 제안을 렌더링합니다.
    public static func renderCLIRecoverySuggestion(
        for error: any AppError,
        positionalValues: [any CustomStringConvertible & Sendable] = [],
        defaultsKey: String = "app.language",
        userDefaults: UserDefaults = .standard,
        base: Bundle = ResourceBundle.localization()
    ) -> String? {
        renderCLIRecoverySuggestion(
            l10nKey: error.l10nKey,
            underlyingError: error.underlyingError,
            context: error.context,
            positionalValues: positionalValues,
            options: CLIOptions(defaultsKey: defaultsKey, userDefaults: userDefaults, base: base)
        )
    }

    /// CLI/Core 환경 컴포넌트 단위 에러 메시지 렌더링.
    public static func renderCLIMessage(
        errorCode: String,
        l10nKey: (any LocalizationKey)?,
        defaultMessage: String? = nil,
        underlyingError: (any Error)? = nil,
        context: [String: String] = [:],
        positionalValues: [any CustomStringConvertible & Sendable] = [],
        options: CLIOptions = CLIOptions()
    ) -> String {
        if let template = resolveCLITemplate(l10nKey: l10nKey, options: options) {
            return substituteSlots(into: template, context: context, positionalValues: positionalValues)
        }
        let fallback = resolveFallbackTemplate(defaultMessage: defaultMessage, underlyingError: underlyingError, errorCode: errorCode)
        return substituteSlots(into: fallback, context: context, positionalValues: positionalValues)
    }

    /// CLI/Core 환경 컴포넌트 단위 복구 제안 렌더링.
    public static func renderCLIRecoverySuggestion(
        l10nKey: (any LocalizationKey)?,
        defaultSuggestion: String? = nil,
        underlyingError: (any Error)? = nil,
        context: [String: String] = [:],
        positionalValues: [any CustomStringConvertible & Sendable] = [],
        options: CLIOptions = CLIOptions()
    ) -> String? {
        if let template = resolveCLIRecoveryTemplate(l10nKey: l10nKey, options: options) {
            return substituteSlots(into: template, context: context, positionalValues: positionalValues)
        }
        guard let fallback = resolveFallbackRecovery(defaultSuggestion: defaultSuggestion, underlyingError: underlyingError) else {
            return nil
        }
        return substituteSlots(into: fallback, context: context, positionalValues: positionalValues)
    }

    // MARK: - Private Helpers

    private static func replaceNamedSlots(in string: String, pattern: String, context: [String: String]) -> String {
        let regex: NSRegularExpression
        do {
            regex = try NSRegularExpression(pattern: pattern)
        } catch {
            return string
        }
        var work = string
        let ns = work as NSString
        let matches = regex.matches(in: work, range: NSRange(location: 0, length: ns.length))
        var replacements: [(NSRange, String)] = []
        for m in matches {
            guard m.numberOfRanges >= 2,
                  let keyRange = Range(m.range(at: 1), in: work),
                  let val = context[String(work[keyRange])] else { continue }
            replacements.append((m.range, val))
        }
        for (range, val) in replacements.sorted(by: { $0.0.location > $1.0.location }) {
            work = (work as NSString).replacingCharacters(in: range, with: val)
        }
        return work
    }

    private static func substitutePositional(
        in work: String,
        context: [String: String],
        positionalValues: [any CustomStringConvertible & Sendable]
    ) -> String {
        if !positionalValues.isEmpty {
            let stringValues: [any CustomStringConvertible] = positionalValues.map { String(describing: $0) }
            return CLILocalization.substituteSlots(into: work, values: stringValues)
        }
        let indexed = extractIndexedValues(from: context)
        guard !indexed.isEmpty else { return work }
        let stringValues: [any CustomStringConvertible] = indexed.map { String(describing: $0) }
        return CLILocalization.substituteSlots(into: work, values: stringValues)
    }

    private static func resolveFallbackTemplate(
        defaultMessage: String?,
        underlyingError: (any Error)?,
        errorCode: String
    ) -> String {
        if let defaultMsg = defaultMessage, !defaultMsg.isEmpty {
            return defaultMsg
        }
        if let underlying = underlyingError {
            return underlying.localizedDescription
        }
        return errorCode.isEmpty ? "UNKNOWN_ERROR" : errorCode
    }

    private static func resolveFallbackRecovery(
        defaultSuggestion: String?,
        underlyingError: (any Error)?
    ) -> String? {
        if let defaultSug = defaultSuggestion, !defaultSug.isEmpty {
            return defaultSug
        }
        guard let localizedError = underlyingError as? LocalizedError,
              let sug = localizedError.recoverySuggestion,
              !sug.isEmpty else {
            return nil
        }
        return sug
    }

    @MainActor
    private static func resolveGUITemplate(
        l10nKey: (any LocalizationKey)?,
        using manager: LocalizationManager
    ) -> String? {
        guard let key = l10nKey else { return nil }
        let rawKey = key.rawValue
        let translated = manager.string(rawKey)
        guard translated != rawKey, !translated.isEmpty else { return nil }
        return translated
    }

    @MainActor
    private static func resolveGUIRecoveryTemplate(
        l10nKey: (any LocalizationKey)?,
        using manager: LocalizationManager
    ) -> String? {
        guard let key = l10nKey else { return nil }
        let recoveryKey = "\(key.rawValue).recovery"
        let translated = manager.string(recoveryKey)
        guard translated != recoveryKey, !translated.isEmpty else { return nil }
        return translated
    }

    private static func resolveCLITemplate(
        l10nKey: (any LocalizationKey)?,
        options: CLIOptions
    ) -> String? {
        guard let key = l10nKey else { return nil }
        let rawKey = key.rawValue
        let translated = CLILocalization.string(
            rawKey,
            defaultsKey: options.defaultsKey,
            userDefaults: options.userDefaults,
            base: options.base
        )
        guard translated != rawKey, !translated.isEmpty else { return nil }
        return translated
    }

    private static func resolveCLIRecoveryTemplate(
        l10nKey: (any LocalizationKey)?,
        options: CLIOptions
    ) -> String? {
        guard let key = l10nKey else { return nil }
        let recoveryKey = "\(key.rawValue).recovery"
        let translated = CLILocalization.string(
            recoveryKey,
            defaultsKey: options.defaultsKey,
            userDefaults: options.userDefaults,
            base: options.base
        )
        guard translated != recoveryKey, !translated.isEmpty else { return nil }
        return translated
    }

    private static func extractIndexedValues(from context: [String: String]) -> [String] {
        guard !context.isEmpty else { return [] }
        let oneBasedKeys = (1...context.count).map(String.init)
        if oneBasedKeys.allSatisfy({ context[$0] != nil }) {
            return oneBasedKeys.compactMap { context[$0] }
        }
        let zeroBasedKeys = (0..<context.count).map(String.init)
        if zeroBasedKeys.allSatisfy({ context[$0] != nil }) {
            return zeroBasedKeys.compactMap { context[$0] }
        }
        return []
    }
}
