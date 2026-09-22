import Foundation
import LocalizationKit

extension AppErrorLocalization {

    // MARK: - Combined LocalizedErrorInfo

    /// 로컬라이즈된 에러 메시지, 복구 제안 및 에러 코드를 묶어 전달하는 불변 값 객체.
    public struct LocalizedErrorInfo: Sendable, Equatable, CustomStringConvertible {
        public let errorCode: String
        public let message: String
        public let recoverySuggestion: String?

        public init(errorCode: String, message: String, recoverySuggestion: String? = nil) {
            self.errorCode = errorCode
            self.message = message
            self.recoverySuggestion = recoverySuggestion
        }

        public var description: String {
            if let recovery = recoverySuggestion, !recovery.isEmpty {
                return "[\(errorCode)] \(message) (Recovery: \(recovery))"
            }
            return "[\(errorCode)] \(message)"
        }
    }

    /// GUI 환경에서 에러 전체 로컬라이즈 정보 렌더링.
    @MainActor
    public static func renderGUI(
        for error: any AppError,
        using manager: LocalizationManager,
        positionalValues: [any CustomStringConvertible & Sendable] = []
    ) -> LocalizedErrorInfo {
        let msg = renderGUIMessage(for: error, using: manager, positionalValues: positionalValues)
        let rec = renderGUIRecoverySuggestion(for: error, using: manager, positionalValues: positionalValues)
        return LocalizedErrorInfo(errorCode: error.errorCode, message: msg, recoverySuggestion: rec)
    }

    /// CLI/Core 환경에서 에러 전체 로컬라이즈 정보 렌더링.
    public static func renderCLI(
        for error: any AppError,
        positionalValues: [any CustomStringConvertible & Sendable] = [],
        defaultsKey: String = "app.language",
        userDefaults: UserDefaults = .standard,
        base: Bundle = ResourceBundle.localization()
    ) -> LocalizedErrorInfo {
        let msg = renderCLIMessage(
            for: error,
            positionalValues: positionalValues,
            defaultsKey: defaultsKey,
            userDefaults: userDefaults,
            base: base
        )
        let rec = renderCLIRecoverySuggestion(
            for: error,
            positionalValues: positionalValues,
            defaultsKey: defaultsKey,
            userDefaults: userDefaults,
            base: base
        )
        return LocalizedErrorInfo(errorCode: error.errorCode, message: msg, recoverySuggestion: rec)
    }

    /// 환경 자동 감지(런타임 스레드/매니저 유무) 기반 통합 렌더링 진입점.
    public static func render(
        error: any AppError,
        using manager: LocalizationManager? = nil,
        positionalValues: [any CustomStringConvertible & Sendable] = []
    ) -> LocalizedErrorInfo {
        guard let manager, Thread.isMainThread else {
            return renderCLI(for: error, positionalValues: positionalValues)
        }
        let stringValues = positionalValues.map { String(describing: $0) }
        return MainActor.assumeIsolated {
            renderGUI(for: error, using: manager, positionalValues: stringValues)
        }
    }
}

// MARK: - AppError Protocol Extension Convenience

extension AppError {
    /// GUI 환경에서 LocalizationManager를 주입받아 완전한 로컬라이즈 정보 생성.
    @MainActor
    public func localizedInfo(
        using manager: LocalizationManager,
        positionalValues: [any CustomStringConvertible & Sendable] = []
    ) -> AppErrorLocalization.LocalizedErrorInfo {
        AppErrorLocalization.renderGUI(for: self, using: manager, positionalValues: positionalValues)
    }

    /// CLI/Core 환경에서 정적 설정 기반으로 완전한 로컬라이즈 정보 생성.
    public func localizedCLIInfo(
        positionalValues: [any CustomStringConvertible & Sendable] = [],
        defaultsKey: String = "app.language",
        userDefaults: UserDefaults = .standard,
        base: Bundle = ResourceBundle.localization()
    ) -> AppErrorLocalization.LocalizedErrorInfo {
        AppErrorLocalization.renderCLI(
            for: self,
            positionalValues: positionalValues,
            defaultsKey: defaultsKey,
            userDefaults: userDefaults,
            base: base
        )
    }
}
