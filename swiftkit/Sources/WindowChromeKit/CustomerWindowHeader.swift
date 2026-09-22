#if canImport(SwiftUI)
import SwiftUI

/// 고객용 단일 룸 뱃지: 복잡한 테넌트/룸 ID 대신 사용자 친화적 작업공간 캡슐 제공
public struct CustomerRoomBadge: View {
    public let title: String
    public let isConnected: Bool

    public init(title: String = "Local Workspace", isConnected: Bool = true) {
        self.title = title
        self.isConnected = isConnected
    }

    public var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(isConnected ? Color.green : Color.secondary)
                .frame(width: 6, height: 6)
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.primary.opacity(0.05), in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("상태: \(title)"))
    }
}

/// 불필요한 팝업이 제거된 고객용 macOS 네이티브 스타일 타이틀바 장식
public struct CustomerTitlebarHeader<Actions: View>: View {
    public let title: String
    public let subtitle: String?
    public let badgeTitle: String?
    private let actions: Actions

    public init(
        title: String,
        subtitle: String? = nil,
        badgeTitle: String? = nil,
        @ViewBuilder actions: () -> Actions = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.badgeTitle = badgeTitle
        self.actions = actions()
    }

    public var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)

                    if let badgeTitle {
                        CustomerRoomBadge(title: badgeTitle)
                    }
                }
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            actions
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        #if canImport(AppKit)
        .background(Color(nsColor: .windowBackgroundColor))
        #endif
    }
}
#endif
