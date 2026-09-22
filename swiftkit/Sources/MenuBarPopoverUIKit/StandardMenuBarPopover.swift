#if os(macOS)
import AppKit
import SwiftUI

/// 메뉴바 팝오버 공용 셸. 헤더 → 본문 → 새로고침/설정 → 종료.
///
/// 제목·버튼 문구는 앱 L10n 을 그대로 받는다. 비우면 그 칸은 그리지 않는다.
public typealias LazyStandardMenuBarPopover<Content: View> = StandardMenuBarPopover<Content>

public struct StandardMenuBarPopover<Content: View>: View {
    private let title: String?
    private let subtitle: String?
    private let errorMessage: String?
    private let width: CGFloat
    private let refreshTitle: String
    private let settingsTitle: String
    private let quitTitle: String
    private let onRefresh: (() async -> Void)?
    private let onOpenSettings: (() -> Void)?
    private let onQuit: (() -> Void)?
    @ViewBuilder private let content: () -> Content

    public init(
        title: String? = nil,
        subtitle: String? = nil,
        errorMessage: String? = nil,
        width: CGFloat = 260,
        refreshTitle: String = "새로고침",
        settingsTitle: String = "설정...",
        quitTitle: String = "종료",
        onRefresh: (() async -> Void)? = nil,
        onOpenSettings: (() -> Void)? = nil,
        onQuit: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.errorMessage = errorMessage
        self.width = width
        self.refreshTitle = refreshTitle
        self.settingsTitle = settingsTitle
        self.quitTitle = quitTitle
        self.onRefresh = onRefresh
        self.onOpenSettings = onOpenSettings
        self.onQuit = onQuit
        self.content = content
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title, !title.isEmpty {
                Text(title).font(.headline)
            }
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            content()

            if let errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(3)
            }

            if onRefresh != nil || onOpenSettings != nil {
                Divider()
                if let onRefresh {
                    Button(refreshTitle) { Task { await onRefresh() } }
                }
                if let onOpenSettings {
                    Button(settingsTitle, action: onOpenSettings)
                }
            }

            Divider()
            Button(quitTitle) {
                if let onQuit {
                    onQuit()
                } else {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .padding(12)
        .frame(width: width)
    }
}
#endif
