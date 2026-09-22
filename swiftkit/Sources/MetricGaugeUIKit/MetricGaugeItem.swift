import SwiftUI

public struct MetricGaugeItem: Identifiable, Sendable {
    public let id: String
    public var label: String
    public var value: Double
    public var min: Double
    public var max: Double
    public var unit: String
    public var thresholdDanger: Double?
    public var tintColor: Color

    public init(
        id: String,
        label: String,
        value: Double,
        min: Double = 0.0,
        max: Double = 1.0,
        unit: String = "",
        thresholdDanger: Double? = nil,
        tintColor: Color = .blue
    ) {
        self.id = id
        self.label = label
        self.value = value
        self.min = min
        self.max = max
        self.unit = unit
        self.thresholdDanger = thresholdDanger
        self.tintColor = tintColor
    }

    public var normalizedValue: Double {
        guard max > min else { return 0.0 }
        let clamped = Swift.min(Swift.max(value, min), max)
        return (clamped - min) / (max - min)
    }

    public var isDangerous: Bool {
        if let thresholdDanger {
            return value >= thresholdDanger
        }
        return false
    }

    public var displayColor: Color {
        isDangerous ? .red : tintColor
    }

    public var formattedValue: String {
        if unit.isEmpty {
            return String(format: "%.1f", value)
        } else {
            return String(format: "%.1f %@", value, unit)
        }
    }
}
