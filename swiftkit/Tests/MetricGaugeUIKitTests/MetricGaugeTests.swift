import XCTest
import SwiftUI
@testable import MetricGaugeUIKit

final class MetricGaugeTests: XCTestCase {
    func testMetricGaugeItemNormalizedValue() {
        let item1 = MetricGaugeItem(
            id: "cpu",
            label: "CPU Load",
            value: 50.0,
            min: 0.0,
            max: 100.0,
            unit: "%"
        )
        XCTAssertEqual(item1.normalizedValue, 0.5, accuracy: 0.001)

        let itemClampedMin = MetricGaugeItem(
            id: "mem",
            label: "Memory",
            value: -10.0,
            min: 0.0,
            max: 100.0
        )
        XCTAssertEqual(itemClampedMin.normalizedValue, 0.0, accuracy: 0.001)

        let itemClampedMax = MetricGaugeItem(
            id: "gpu",
            label: "GPU",
            value: 150.0,
            min: 0.0,
            max: 100.0
        )
        XCTAssertEqual(itemClampedMax.normalizedValue, 1.0, accuracy: 0.001)
    }

    func testMetricGaugeItemDangerThreshold() {
        let safeItem = MetricGaugeItem(
            id: "temp",
            label: "Temperature",
            value: 65.0,
            min: 0.0,
            max: 100.0,
            thresholdDanger: 80.0
        )
        XCTAssertFalse(safeItem.isDangerous)

        let dangerItem = MetricGaugeItem(
            id: "temp_hot",
            label: "Temperature Hot",
            value: 85.0,
            min: 0.0,
            max: 100.0,
            thresholdDanger: 80.0
        )
        XCTAssertTrue(dangerItem.isDangerous)
    }

    func testWaveDataPointCreation() {
        let point = WaveDataPoint(index: 42, amplitude: 0.85)
        XCTAssertEqual(point.index, 42)
        XCTAssertEqual(point.amplitude, 0.85, accuracy: 0.001)
        XCTAssertFalse(point.id.uuidString.isEmpty)
    }
}
