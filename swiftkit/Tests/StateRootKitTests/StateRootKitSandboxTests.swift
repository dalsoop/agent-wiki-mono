import XCTest
@testable import StateRootKit

final class StateRootKitSandboxTests: XCTestCase {
    func testIsInsideRoomSandboxTrueWhenRoomIdOrSandboxPath() {
        XCTAssertTrue(StateRootKit.isInsideRoomSandbox(["SANDBOX_ROOM_ID": "room-1"]))
        XCTAssertTrue(StateRootKit.isInsideRoomSandbox([
            "SWIFT_APP_STATE_ROOT": "/Users/tester/.sandboxes/room-abc/state"
        ]))
        XCTAssertTrue(StateRootKit.isInsideRoomSandbox([
            "SWIFT_APP_STATE_ROOT": "/tmp/room-abc/state"
        ]))
    }

    func testIsInsideRoomSandboxFalseWithoutMarkers() {
        XCTAssertFalse(StateRootKit.isInsideRoomSandbox([:]))
        XCTAssertFalse(StateRootKit.isInsideRoomSandbox([
            "SWIFT_APP_STATE_ROOT": "/tmp/fixture-root"
        ]))
        XCTAssertFalse(StateRootKit.isInsideRoomSandbox([
            "XCTestConfigurationFilePath": "/x"
        ]))
    }
}
