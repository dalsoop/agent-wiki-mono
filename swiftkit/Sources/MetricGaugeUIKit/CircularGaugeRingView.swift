import SwiftUI

public struct CircularGaugeRingView: View {
    public let item: MetricGaugeItem
    public var lineWidth: CGFloat
    public var showCenterText: Bool

    public init(
        item: MetricGaugeItem,
        lineWidth: CGFloat = 8.0,
        showCenterText: Bool = true
    ) {
        self.item = item
        self.lineWidth = lineWidth
        self.showCenterText = showCenterText
    }

    public var body: some View {
        ZStack {
            // 배경 트랙
            Circle()
                .stroke(Color.secondary.opacity(0.15), lineWidth: lineWidth)

            // 충전 링
            Circle()
                .trim(from: 0.0, to: CGFloat(item.normalizedValue))
                .stroke(
                    item.displayColor,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: item.value)

            if showCenterText {
                VStack(spacing: 2) {
                    Text(item.label)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(item.formattedValue)
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(item.displayColor)
                }
                .padding(4)
            }
        }
    }
}
