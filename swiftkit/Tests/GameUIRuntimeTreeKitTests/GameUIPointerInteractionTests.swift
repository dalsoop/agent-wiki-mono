import XCTest
@testable import GameUIRuntimeTreeKit

final class GameUIPointerInteractionTests: XCTestCase {
    func testPrimaryActionRequiresReleaseOnPressedIdentity() {
        let root = twoButtonFixture()
        var pointer = GameUIPointerInteractionState()
        _ = pointer.pointerDown(at: .init(x: 25, y: 25), in: root)
        let release = pointer.pointerUp(at: .init(x: 125, y: 25), in: root)

        XCTAssertNil(release.actionID)
        XCTAssertNil(pointer.pressedIdentity)
    }

    func testReleaseOnPressedIdentityFiresUpAction() {
        let root = twoButtonFixture()
        var pointer = GameUIPointerInteractionState()
        let down = pointer.pointerDown(at: .init(x: 25, y: 25), in: root)
        let release = pointer.pointerUp(at: .init(x: 25, y: 25), in: root)

        XCTAssertEqual(down.actionID, "left-down")
        XCTAssertEqual(release.actionID, "left-up")
    }

    func testCapturedIdentitySurvivesPointerLeavingBoundsUntilRelease() {
        let root = GameUIRuntimeNode(
            id: "root",
            layout: .init(frame: .init(x: 0, y: 0, width: 100, height: 100)),
            children: [
                GameUIRuntimeNode(
                    id: "drag",
                    layout: .init(frame: .init(x: 0, y: 0, width: 50, height: 50)),
                    interaction: .init(
                        upActionID: "drop",
                        capturesPointer: true
                    )
                ),
            ]
        )
        var pointer = GameUIPointerInteractionState()

        _ = pointer.pointerDown(at: .init(x: 25, y: 25), in: root)
        XCTAssertEqual(pointer.capturedIdentity, ["root", "drag"])
        _ = pointer.pointerMove(at: .init(x: 500, y: 500), in: root)
        XCTAssertEqual(pointer.capturedIdentity, ["root", "drag"])
        let release = pointer.pointerUp(at: .init(x: 500, y: 500), in: root)
        XCTAssertNil(release.actionID)
        XCTAssertNil(pointer.capturedIdentity)
    }

    func testHoverOnlyFiresWhenIdentityChanges() {
        let root = twoButtonFixture()
        var pointer = GameUIPointerInteractionState()

        XCTAssertEqual(
            pointer.pointerMove(at: .init(x: 25, y: 25), in: root).actionID,
            "left-hover"
        )
        XCTAssertNil(pointer.pointerMove(at: .init(x: 26, y: 25), in: root).actionID)
        XCTAssertEqual(
            pointer.pointerMove(at: .init(x: 125, y: 25), in: root).actionID,
            "right-hover"
        )
    }

    func testSameRepeatedKeyOnDifferentControlsCannotCompletePrimaryAction() {
        let root = GameUIRuntimeNode(
            id: "root",
            layout: .init(frame: .init(x: 0, y: 0, width: 200, height: 100)),
            children: [
                GameUIRuntimeNode(
                    id: "left",
                    repeatedKey: "shared",
                    layout: .init(frame: .init(x: 0, y: 0, width: 100, height: 100)),
                    interaction: .init(upActionID: "left")
                ),
                GameUIRuntimeNode(
                    id: "right",
                    repeatedKey: "shared",
                    layout: .init(frame: .init(x: 100, y: 0, width: 100, height: 100)),
                    interaction: .init(upActionID: "right")
                ),
            ]
        )
        var pointer = GameUIPointerInteractionState()

        _ = pointer.pointerDown(at: .init(x: 25, y: 25), in: root)
        let release = pointer.pointerUp(at: .init(x: 125, y: 25), in: root)

        XCTAssertNil(release.actionID)
    }

    private func twoButtonFixture() -> GameUIRuntimeNode {
        GameUIRuntimeNode(
            id: "root",
            layout: .init(frame: .init(x: 0, y: 0, width: 200, height: 100)),
            children: [
                GameUIRuntimeNode(
                    id: "left",
                    layout: .init(frame: .init(x: 0, y: 0, width: 100, height: 100)),
                    interaction: .init(
                        downActionID: "left-down",
                        upActionID: "left-up",
                        hoverActionID: "left-hover"
                    )
                ),
                GameUIRuntimeNode(
                    id: "right",
                    layout: .init(frame: .init(x: 100, y: 0, width: 100, height: 100)),
                    interaction: .init(
                        downActionID: "right-down",
                        upActionID: "right-up",
                        hoverActionID: "right-hover"
                    )
                ),
            ]
        )
    }
}
