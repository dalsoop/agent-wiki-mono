import SwiftUI

public enum GaugeOrientation: Sendable {
    case horizontal
    case vertical
}

public struct LinearGaugeBarView: View {
    public let item: MetricGaugeItem
    public var orientation: GaugeOrientation
    public var height: CGFloat
    public var showLabels: Bool

    public init(
        item: MetricGaugeItem,
        orientation: GaugeOrientation = .horizontal,
        height: CGFloat = 8.0,
        showLabels: Bool = true
    ) {
        self.item = item
        self.orientation = orientation
        self.height = height
        self.showLabels = showLabels
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if showLabels {
                HStack {
                    Text(item.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(item.formattedValue)
                        .font(.caption.monospacedDigit())
                        .bold()
                        .foregroundStyle(item.displayColor)
                }
            }

            GeometryReader { proxy in
                let normalized = item.normalizedValue
                ZStack(alignment: orientation == .horizontal ? .leading : .bottom) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.2))

                    if orientation == .horizontal {
                        Capsule()
                            .fill(item.displayColor)
                            .frame(width: max(proxy.size.width * CGFloat(normalized), 4))
                            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: item.value)
                    } else {
                        Capsule()
                            .fill(item.displayColor)
                            .frame(height: max(proxy.size.height * CGFloat(normalized), 4))
                            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: item.value)
                    }
                }
            }
            .frame(
                width: orientation == .vertical ? height : nil,
                height: orientation == .horizontal ? height : nil
            )
        }
    }
}
