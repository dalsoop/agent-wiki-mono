import XCTest
import SwiftUI
@testable import InteractiveGestureHapticKit

final class HapticGestureTests: XCTestCase {

    func testHapticFeedbackPresets() {
        let click = HapticFeedbackPreset.transientClick
        let light = HapticFeedbackPreset.impactLight
        let heavy = HapticFeedbackPreset.impactHeavy
        let pulse = HapticFeedbackPreset.periodicMicroPulse(frequencyHz: 30.0, intensity: 0.7)

        XCTAssertNotEqual(click, light)
        XCTAssertNotEqual(light, heavy)
        XCTAssertEqual(pulse, .periodicMicroPulse(frequencyHz: 30.0, intensity: 0.7))

        // gentleRumble alias test
        let rumble = HapticFeedbackPreset.gentleRumble(intensity: 0.4)
        XCTAssertEqual(rumble, .periodicMicroPulse(frequencyHz: 25.0, intensity: 0.4))
    }

    func testFrictionDragValue() {
        let val = FrictionDragValue(
            velocity: 150.5,
            cumulativeDistance: 45.0,
            duration: 0.3
        )

        XCTAssertEqual(val.velocity, 150.5)
        XCTAssertEqual(val.cumulativeDistance, 45.0)
        XCTAssertEqual(val.duration, 0.3)
    }

    @MainActor
    func testHapticFeedbackEngineTrigger() {
        let presets: [HapticFeedbackPreset] = [
            .transientClick,
            .impactLight,
            .impactHeavy,
            .gentleRumble(intensity: 0.5),
            .periodicMicroPulse(frequencyHz: 50.0, intensity: 0.8)
        ]
        XCTAssertEqual(presets.count, 5)
        for preset in presets {
            HapticFeedbackEngine.trigger(preset)
        }
        #if os(macOS)
        XCTAssertNotNil(NSHapticFeedbackManager.defaultPerformer)
        #endif
    }
}
