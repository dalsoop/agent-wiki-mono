import SwiftUI

/// 인라인 알림/경고/에러 배너의 스타일 유형.
public enum NoticeBannerStyle: Sendable {
    case info
    case success
    case warning
    case error

    public var systemImage: String {
        switch self {
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.circle.fill"
        }
    }

    public var color: Color {
        switch self {
        case .info: return .blue
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }
}

/// 인라인 상태 알림 및 피드백 배너 컴포넌트.
public struct NoticeBanner: View {
    private let message: String
    private let style: NoticeBannerStyle
    private let actionTitle: String?
    private let action: (() -> Void)?
    private let onDismiss: (() -> Void)?

    public init(
        _ message: String,
        style: NoticeBannerStyle = .info,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.message = message
        self.style = style
        self.actionTitle = actionTitle
        self.action = action
        self.onDismiss = onDismiss
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: style.systemImage)
                .foregroundStyle(style.color)
                .font(.callout)

            Text(message)
                .font(.caption)
                .foregroundStyle(style.color)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let actionTitle, let action {
                Button(actionTitle) {
                    action()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if let onDismiss = onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption2)
                        .foregroundStyle(style.color.opacity(0.8))
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(style.color.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(style.color.opacity(0.2), lineWidth: 1)
        )
    }
}

/// 옵셔널 에러 메시지를 받아 표시하는 에러 전용 배너.
///
/// 200여 개 뷰에서 쓰이던 `if let err = model.lastError { ... }` 코드를 1줄로 축소한다.
public struct ErrorBanner: View {
    private let error: String?
    private let actionTitle: String?
    private let action: (() -> Void)?
    private let onDismiss: (() -> Void)?

    public init(
        _ error: String?,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.error = error
        self.actionTitle = actionTitle
        self.action = action
        self.onDismiss = onDismiss
    }

    public var body: some View {
        if let error = error, !error.isEmpty {
            NoticeBanner(
                error,
                style: .error,
                actionTitle: actionTitle,
                action: action,
                onDismiss: onDismiss
            )
        }
    }
}
