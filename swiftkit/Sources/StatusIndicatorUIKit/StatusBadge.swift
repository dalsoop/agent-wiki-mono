import SwiftUI

/// 상태 뱃지 및 인디케이터의 색상/의미 톤.
public enum StatusIndicatorTone: Sendable {
    case success
    case warning
    case error
    case running
    case idle
    case custom(Color)

    public var color: Color {
        switch self {
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        case .running: return .blue
        case .idle: return .secondary
        case .custom(let color): return color
        }
    }
}

/// 상태를 나타내는 원형 점 인디케이터.
public struct StatusDot: View {
    private let tone: StatusIndicatorTone
    private let size: CGFloat

    public init(tone: StatusIndicatorTone, size: CGFloat = 8) {
        self.tone = tone
        self.size = size
    }

    public var body: some View {
        Circle()
            .fill(tone.color)
            .frame(width: size, height: size)
    }
}

/// 캡슐 형태의 표준 상태 뱃지 UI 컴포넌트.
///
/// 50여 개 앱에서 수동으로 `Capsule()`, `color.opacity(0.14)`를 조합하던 코드를 통합한다.
public struct StatusBadge: View {
    private let title: String
    private let tone: StatusIndicatorTone
    private let showDot: Bool

    public init(
        title: String,
        tone: StatusIndicatorTone = .idle,
        showDot: Bool = false
    ) {
        self.title = title
        self.tone = tone
        self.showDot = showDot
    }

    public var body: some View {
        HStack(spacing: 4) {
            if showDot {
                StatusDot(tone: tone, size: 6)
            }
            Text(title)
                .font(.caption2.weight(.medium))
                .lineLimit(1)
                .frame(minWidth: 20)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 2.5)
        .background(tone.color.opacity(0.14), in: Capsule())
        .foregroundStyle(tone.color)
    }
}
