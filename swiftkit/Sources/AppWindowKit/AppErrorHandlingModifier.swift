#if canImport(AppKit) && canImport(SwiftUI)
import AppKit
import SwiftUI
import os
import AppErrorKit
import LocalizationKit
import NoticeBannerUIKit

private let logger = Logger(subsystem: "com.gujo.appwindow", category: "AppErrorHandling")

// MARK: - Environment Support

private struct LocalizationManagerKey: EnvironmentKey {
    static let defaultValue: LocalizationManager? = nil
}

public extension EnvironmentValues {
    /// SwiftUI 환경 계층을 통해 주입되는 `LocalizationManager` 인스턴스.
    var localizationManager: LocalizationManager? {
        get { self[LocalizationManagerKey.self] }
        set { self[LocalizationManagerKey.self] = newValue }
    }
}

// MARK: - AppErrorHandlingModifier

/// 최상위 윈도우에 투명하게 부착되는 에러 처리 그물망 뷰 모디파이어.
///
/// - 외부 바인딩(`Binding<AnyAppError?>`) 또는 `AppErrorReporter`의 전역 노티피케이션을 구독합니다.
/// - `error.isSilent`인 경우(CancellationError 등) 화면 팝업/배너를 띄우지 않고 디버그 로그만 기록합니다.
/// - 일반 에러는 다국어 번역(`AppErrorLocalization.render`)을 거쳐 최상단 `NoticeBanner`로 띄웁니다.
/// - 복구 제안(`recoverySuggestion`) 또는 `onRecovery` 콜백이 있으면 배너 액션 버튼으로 연동합니다.
public struct AppErrorHandlingModifier: ViewModifier {
    @Binding private var externalError: AnyAppError?
    private let hasExternalBinding: Bool
    private let subscribeToReporter: Bool
    private let customLocalizationManager: LocalizationManager?
    private let customActionTitle: String?
    private let onRecovery: ((AnyAppError) -> Void)?
    private let onDismiss: ((AnyAppError) -> Void)?

    @Environment(\.localizationManager) private var envLocalizationManager
    @State private var internalError: AnyAppError?

    public init(
        error: Binding<AnyAppError?>? = nil,
        subscribeToReporter: Bool = true,
        localizationManager: LocalizationManager? = nil,
        actionTitle: String? = nil,
        onRecovery: ((AnyAppError) -> Void)? = nil,
        onDismiss: ((AnyAppError) -> Void)? = nil
    ) {
        if let error {
            self._externalError = error
            self.hasExternalBinding = true
        } else {
            self._externalError = .constant(nil)
            self.hasExternalBinding = false
        }
        self.subscribeToReporter = subscribeToReporter
        self.customLocalizationManager = localizationManager
        self.customActionTitle = actionTitle
        self.onRecovery = onRecovery
        self.onDismiss = onDismiss
    }

    private var currentError: AnyAppError? {
        hasExternalBinding ? externalError : internalError
    }

    private var effectiveLocalizationManager: LocalizationManager? {
        customLocalizationManager ?? envLocalizationManager
    }

    @ViewBuilder
    private var topBannerInset: some View {
        if let error = currentError, !error.isSilent {
            errorBannerView(for: error)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)
                .background(Color(nsColor: .windowBackgroundColor).opacity(0.95))
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    public func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                topBannerInset
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: currentError)
            .modifier(BindingChangeObserver(value: externalError, action: handleBindingErrorChange))
            .onReceive(NotificationCenter.default.publisher(for: AppErrorReporter.didRecordErrorNotification)) { notification in
                handleIncomingNotification(notification)
            }
    }

    private func handleIncomingNotification(_ notification: Notification) {
        guard subscribeToReporter else { return }
        guard let incoming = extractAppError(from: notification) else { return }
        guard !incoming.isSilent else {
            logger.debug("Silent error suppressed from notification: [\(incoming.errorCode)] \(incoming.description)")
            return
        }

        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            assignIncomingError(incoming)
        }
    }

    private func assignIncomingError(_ error: AnyAppError) {
        if hasExternalBinding {
            externalError = error
        } else {
            internalError = error
        }
    }

    private func handleBindingErrorChange(_ newError: AnyAppError?) {
        guard let newError, newError.isSilent else { return }
        logger.debug("Silent error suppressed from binding: [\(newError.errorCode)] \(newError.description)")
        Task { @MainActor in
            self.externalError = nil
        }
    }

    @ViewBuilder
    private func errorBannerView(for error: AnyAppError) -> some View {
        let info = AppErrorLocalization.render(error: error, using: effectiveLocalizationManager)
        let style = bannerStyle(for: error.severity)
        let (actionText, actionBlock) = resolveAction(for: error, info: info)

        let displayMessage: String = {
            if let recovery = info.recoverySuggestion, !recovery.isEmpty, actionText == nil {
                return "\(info.message)\n\(recovery)"
            }
            return info.message
        }()

        NoticeBanner(
            displayMessage,
            style: style,
            actionTitle: actionText,
            action: actionBlock,
            onDismiss: {
                dismissError(error)
            }
        )
    }

    private func resolveAction(
        for error: AnyAppError,
        info: AppErrorLocalization.LocalizedErrorInfo
    ) -> (String?, (() -> Void)?) {
        let suggestion = info.recoverySuggestion?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let customActionTitle {
            let action: () -> Void = {
                dismissError(error)
                onRecovery?(error)
            }
            return (customActionTitle, action)
        }

        return resolveDefaultOrSuggestionAction(for: error, suggestion: suggestion)
    }

    private func resolveDefaultOrSuggestionAction(
        for error: AnyAppError,
        suggestion: String?
    ) -> (String?, (() -> Void)?) {
        if let onRecovery {
            let title = defaultActionTitle(from: suggestion)
            return (title, {
                dismissError(error)
                onRecovery(error)
            })
        }

        guard let suggestion, !suggestion.isEmpty else {
            return (nil, nil)
        }

        let title = suggestion.count <= 18 ? suggestion : defaultActionTitle(from: nil)
        return (title, { dismissError(error) })
    }

    private func defaultActionTitle(from suggestion: String?) -> String {
        if let suggestion, !suggestion.isEmpty, suggestion.count <= 18 {
            return suggestion
        }
        return localizedRetryTitle()
    }

    private func localizedRetryTitle() -> String {
        if let manager = effectiveLocalizationManager {
            let key = "app.error.action.retry"
            let translated = manager.string(key)
            if translated != key { return translated }
        }
        let isKorean = Locale.current.language.languageCode?.identifier == "ko"
        return isKorean ? "다시 시도" : "Retry"
    }

    private func dismissError(_ error: AnyAppError) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if hasExternalBinding {
                externalError = nil
            }
            internalError = nil
        }
        onDismiss?(error)
    }

    private func bannerStyle(for severity: ErrorSeverity) -> NoticeBannerStyle {
        switch severity {
        case .info:
            return .info
        case .warning:
            return .warning
        case .error, .critical:
            return .error
        }
    }

    private func extractAppError(from notification: Notification) -> AnyAppError? {
        if let anyError = notification.object as? AnyAppError {
            return anyError
        }
        if let appError = notification.object as? any AppError {
            return AnyAppError(appError)
        }
        return nil
    }
}

// MARK: - View Extensions

public extension View {
    /// 최상위 윈도우에 투명 그물망 에러 처리 배너를 부착합니다.
    ///
    /// - Parameters:
    ///   - error: 관찰할 선택적 에러 바인딩. nil이면 내부 상태로 에러를 수신합니다.
    ///   - subscribeToReporter: `AppErrorReporter.didRecordErrorNotification` 전역 알림을 수신할지 여부. 기본값 `true`.
    ///   - localizationManager: 다국어 번역 매니저. nil이면 환경값(`\.localizationManager`)을 우선 사용합니다.
    ///   - actionTitle: 복구 액션 버튼 커스텀 라벨.
    ///   - onRecovery: 복구 액션 버튼 클릭 시 호출되는 핸들러.
    ///   - onDismiss: 배너가 닫힐 때 호출되는 핸들러.
    func appErrorHandling(
        error: Binding<AnyAppError?>? = nil,
        subscribeToReporter: Bool = true,
        localizationManager: LocalizationManager? = nil,
        actionTitle: String? = nil,
        onRecovery: ((AnyAppError) -> Void)? = nil,
        onDismiss: ((AnyAppError) -> Void)? = nil
    ) -> some View {
        modifier(
            AppErrorHandlingModifier(
                error: error,
                subscribeToReporter: subscribeToReporter,
                localizationManager: localizationManager,
                actionTitle: actionTitle,
                onRecovery: onRecovery,
                onDismiss: onDismiss
            )
        )
    }

    /// 바인딩 기반 에러 핸들링 편의 메서드.
    func appErrorHandling(
        error: Binding<AnyAppError?>,
        localizationManager: LocalizationManager? = nil,
        actionTitle: String? = nil,
        onRecovery: ((AnyAppError) -> Void)? = nil,
        onDismiss: ((AnyAppError) -> Void)? = nil
    ) -> some View {
        appErrorHandling(
            error: error as Binding<AnyAppError?>?,
            subscribeToReporter: false,
            localizationManager: localizationManager,
            actionTitle: actionTitle,
            onRecovery: onRecovery,
            onDismiss: onDismiss
        )
    }

    /// 전역 리포터 구독 기반 투명 그물망 편의 메서드.
    func appErrorHandling(
        subscribeToReporter: Bool = true,
        localizationManager: LocalizationManager? = nil,
        actionTitle: String? = nil,
        onRecovery: ((AnyAppError) -> Void)? = nil,
        onDismiss: ((AnyAppError) -> Void)? = nil
    ) -> some View {
        appErrorHandling(
            error: nil,
            subscribeToReporter: subscribeToReporter,
            localizationManager: localizationManager,
            actionTitle: actionTitle,
            onRecovery: onRecovery,
            onDismiss: onDismiss
        )
    }
}

// MARK: - Backward-compatible Binding Observer

private struct BindingChangeObserver<T: Equatable>: ViewModifier {
    let value: T
    let action: (T) -> Void

    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content.onChange(of: value) { _, newValue in
                action(newValue)
            }
        } else {
            content.onChange(of: value) { newValue in
                action(newValue)
            }
        }
    }
}
#endif
