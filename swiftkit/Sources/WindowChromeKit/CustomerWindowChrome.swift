#if canImport(SwiftUI)
import SwiftUI

/// [D4] 고객용 네이티브 창 테두리 및 단일 룸 결합 컨테이너
public struct CustomerWindowChrome<Content: View, Actions: View, Footer: View>: View {
    public let binding: CustomerRoomBinding
    public let windowTitle: String
    public let subtitle: String?
    public let badgeTitle: String?
    private let actions: Actions
    private let content: Content
    private let footer: Footer?

    public init(
        binding: CustomerRoomBinding,
        windowTitle: String,
        subtitle: String? = nil,
        badgeTitle: String? = nil,
        @ViewBuilder actions: () -> Actions = { EmptyView() },
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer = { EmptyView() }
    ) {
        self.binding = binding
        self.windowTitle = windowTitle
        self.subtitle = subtitle
        self.badgeTitle = badgeTitle
        self.actions = actions()
        self.content = content()
        self.footer = footer()

        // 기동 시 저장소 자동 보장
        binding.ensureStorage()
    }

    public var body: some View {
        VStack(spacing: 0) {
            CustomerTitlebarHeader(
                title: windowTitle,
                subtitle: subtitle,
                badgeTitle: badgeTitle,
                actions: { actions }
            )

            Divider()

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let footer {
                Divider()
                footer
                    #if canImport(AppKit)
                    .background(Color(nsColor: .windowBackgroundColor))
                    #endif
            }
        }
        #if canImport(AppKit)
        .background(Color(nsColor: .windowBackgroundColor))
        #endif
    }
}
#endif
