#if os(macOS)
import SwiftUI
import MoneyInflowKit

public struct DeadlineCopy: Sendable, Equatable {
    public var today: String
    public var closed: String
    public var alwaysOpen: String

    public init(today: String = "오늘 마감", closed: String = "마감", alwaysOpen: String = "상시") {
        self.today = today
        self.closed = closed
        self.alwaysOpen = alwaysOpen
    }
}

public struct ScoreCircle: View {
    public var score: Int
    public var high: Int
    public var mid: Int
    public var low: Int

    public init(score: Int, high: Int = 80, mid: Int = 60, low: Int = 40) {
        self.score = score
        self.high = high
        self.mid = mid
        self.low = low
    }

    public var body: some View {
        ZStack {
            Circle().fill(color.opacity(0.16)).frame(width: 44, height: 44)
            Text("\(score)").font(.headline.bold()).foregroundStyle(color).monospacedDigit()
        }
    }

    private var color: Color {
        if score >= high { return .green }
        if score >= mid { return .blue }
        if score >= low { return .orange }
        return .secondary
    }
}

public struct FlowChips: View {
    public var items: [String]

    public init(items: [String]) {
        self.items = items
    }

    public var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), alignment: .leading)], alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { r in
                Text(r).font(.caption)
                    .lineLimit(1)
                    .frame(minWidth: 0)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
            }
        }
    }
}

public struct DeadlineBadge: View {
    public var period: ApplicationPeriod
    public var prominent: Bool
    public var copy: DeadlineCopy

    public init(period: ApplicationPeriod, prominent: Bool = false, copy: DeadlineCopy = DeadlineCopy()) {
        self.period = period
        self.prominent = prominent
        self.copy = copy
    }

    public var body: some View {
        Group {
            if let d = period.daysUntilClose(), d >= 0 {
                label(d == 0 ? copy.today : "D-\(d)", color: d <= 3 ? .red : .accentColor)
            } else if period.end != nil {
                label(copy.closed, color: .secondary)
            } else {
                label(copy.alwaysOpen, color: .green)
            }
        }
        .font(prominent ? .callout.bold() : .caption)
    }

    private func label(_ text: String, color: Color) -> some View {
        Text(text)
            .lineLimit(1)
            .frame(minWidth: 0)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(prominent ? 0.15 : 0.12), in: Capsule())
            .foregroundStyle(color)
    }
}
#endif
