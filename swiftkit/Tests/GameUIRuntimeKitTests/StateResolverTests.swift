import XCTest

@testable import GameUIRuntimeKit

final class StateResolverTests: XCTestCase {
  func testDisabledBindingWinsOverPressedState() throws {
    let store = GameUIBindingStore(values: ["confirmDisabled": .boolean(true)])

    XCTAssertEqual(
      try GameUIStateResolver.buttonState(
        disabledBinding: "confirmDisabled",
        isPressed: true,
        store: store
      ),
      .disabled
    )
  }

  func testPressedAndNormalStatesResolveWithoutDisabledBinding() throws {
    let store = GameUIBindingStore(values: [:])

    XCTAssertEqual(
      try GameUIStateResolver.buttonState(disabledBinding: nil, isPressed: true, store: store),
      .pressed
    )
    XCTAssertEqual(
      try GameUIStateResolver.buttonState(disabledBinding: nil, isPressed: false, store: store),
      .normal
    )
  }

  func testActionRouterSuppressesDisabledAction() {
    var actions: [GameUIAction] = []
    let router = GameUIActionRouter { actions.append($0) }

    XCTAssertFalse(router.send(actionID: "confirm", isEnabled: false))
    XCTAssertTrue(router.send(actionID: "return", isEnabled: true))
    XCTAssertEqual(actions, [GameUIAction(id: "return")])
  }
}
