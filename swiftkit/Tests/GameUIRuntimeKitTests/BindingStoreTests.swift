import XCTest

@testable import GameUIRuntimeKit

final class BindingStoreTests: XCTestCase {
  func testLooksUpNestedValueByDottedKey() throws {
    let store = GameUIBindingStore(values: [
      "territories": .object([
        "ember": .object(["health": .number(72)])
      ])
    ])

    XCTAssertEqual(try store.value(for: "territories.ember.health"), .number(72))
  }

  func testMissingKeyThrowsTypedError() {
    let store = GameUIBindingStore(values: [:])

    XCTAssertThrowsError(try store.value(for: "resources.gold")) { error in
      XCTAssertEqual(error as? GameUIBindingError, .missingKey("resources"))
    }
  }

  func testMeterFractionUsesCurrentAndMax() throws {
    let store = GameUIBindingStore(values: [
      "health": .object(["current": .number(25), "max": .number(100)])
    ])

    XCTAssertEqual(try store.meterValue(for: "health").fraction, 0.25, accuracy: 0.0001)
  }

  func testMeterFractionClampsToUnitRange() throws {
    let over = GameUIBindingStore(values: [
      "meter": .object(["current": .number(150), "max": .number(100)])
    ])
    let under = GameUIBindingStore(values: [
      "meter": .object(["current": .number(-10), "max": .number(100)])
    ])

    XCTAssertEqual(try over.meterValue(for: "meter").fraction, 1)
    XCTAssertEqual(try under.meterValue(for: "meter").fraction, 0)
  }

  func testZeroMeterMaximumThrowsTypedError() {
    let store = GameUIBindingStore(values: [
      "health": .object(["current": .number(25), "max": .number(0)])
    ])

    XCTAssertThrowsError(try store.meterValue(for: "health")) { error in
      XCTAssertEqual(error as? GameUIBindingError, .invalidMeterMaximum("health"))
    }
  }
}
