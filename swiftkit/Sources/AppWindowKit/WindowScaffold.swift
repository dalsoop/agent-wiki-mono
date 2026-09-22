#if canImport(AppKit) && canImport(SwiftUI)
import AppKit
import SwiftUI
import AppErrorKit
import LocalizationKit
import NoticeBannerUIKit

/// 표준 윈도우 스캐폴드 컴포넌트.
///
/// 상단 투명 에러 그물망 배너(`appErrorHandling`), 중앙 본문 콘텐츠,
/// 선택적 하단 푸터 바(`scaffoldFooterBar`)를 단일 선언으로 일체화합니다.
///
/// 사용 예:
/// ```swift
/// WindowScaffold {
///     ContentView()
/// }
///
/// WindowScaffold(error: $model.currentError, onRecovery: { err in model.retry() }) {
///     FooterView()
/// } content: {
///     ContentView()
/// }
/// ```
public struct WindowScaffold<Content: View, Footer: View>: View {
    private let errorBinding: Binding<AnyAppError?>?
    private let subscribeToReporter: Bool
    private let localizationManager: LocalizationManager?
    private let actionTitle: String?
    private let onRecovery: ((AnyAppError) -> Void)?
    private let onDismiss: ((AnyAppError) -> Void)?
    private let content: Content
    private let footer: Footer?

    public init(
        error: Binding<AnyAppError?>? = nil,
        subscribeToReporter: Bool = true,
        localizationManager: LocalizationManager? = nil,
        actionTitle: String? = nil,
        onRecovery: ((AnyAppError) -> Void)? = nil,
        onDismiss: ((AnyAppError) -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) where Footer == EmptyView {
        self.errorBinding = error
        self.subscribeToReporter = subscribeToReporter
        self.localizationManager = localizationManager
        self.actionTitle = actionTitle
        self.onRecovery = onRecovery
        self.onDismiss = onDismiss
        self.content = content()
        self.footer = nil
    }

    public init(
        error: Binding<AnyAppError?>? = nil,
        subscribeToReporter: Bool = true,
        localizationManager: LocalizationManager? = nil,
        actionTitle: String? = nil,
        onRecovery: ((AnyAppError) -> Void)? = nil,
        onDismiss: ((AnyAppError) -> Void)? = nil,
        @ViewBuilder footer: () -> Footer,
        @ViewBuilder content: () -> Content
    ) {
        self.errorBinding = error
        self.subscribeToReporter = subscribeToReporter
        self.localizationManager = localizationManager
        self.actionTitle = actionTitle
        self.onRecovery = onRecovery
        self.onDismiss = onDismiss
        self.footer = footer()
        self.content = content()
    }

    public var body: some View {
        Group {
            if let footer {
                content
                    .scaffoldFooterBar {
                        footer
                    }
            } else {
                content
            }
        }
        .appErrorHandling(
            error: errorBinding,
            subscribeToReporter: subscribeToReporter,
            localizationManager: localizationManager,
            actionTitle: actionTitle,
            onRecovery: onRecovery,
            onDismiss: onDismiss
        )
    }
}
#endif
