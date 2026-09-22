#if canImport(AppKit) && canImport(SwiftUI)
import AppKit
import SwiftUI

/// 창 하단에 상태바나 액션 툴바를 안전하게 배치하는 표준 뷰 모디파이어.
///
/// - `Divider()`를 상단에 자동 배치하여 본문 스크롤 영역과 하단 바를 시각적으로 명확히 분리합니다.
/// - 완전 불투명한 시스템 창 배경색(`Color(nsColor: .windowBackgroundColor)`)을 강제하여
///   하단 스크롤 내용이 반투명하게 비치는 bleed-through 현상을 원천 차단합니다.
/// - `safeAreaInset(edge: .bottom, spacing: 0)`을 표준 규격으로 캡슐화합니다.
public struct ScaffoldFooterBarModifier<Footer: View>: ViewModifier {
    private let footer: Footer

    public init(@ViewBuilder footer: () -> Footer) {
        self.footer = footer()
    }

    public func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    Divider()
                    footer
                }
                .background(Color(nsColor: .windowBackgroundColor))
            }
    }
}

public extension View {
    /// 창 하단에 불투명 배경 및 Divider가 보장된 표준 푸터 바를 부착합니다.
    ///
    /// 개별 앱에서 `safeAreaInset(edge: .bottom)`을 직접 날것으로 작성하지 않고
    /// 이 표준 모디파이어를 사용하여 비침 결함을 원천 차단합니다.
    ///
    /// ```swift
    /// ContentView()
    ///     .scaffoldFooterBar {
    ///         StatusBarView()
    ///     }
    /// ```
    func scaffoldFooterBar<Footer: View>(@ViewBuilder _ footer: () -> Footer) -> some View {
        modifier(ScaffoldFooterBarModifier(footer: footer))
    }
}
#endif
