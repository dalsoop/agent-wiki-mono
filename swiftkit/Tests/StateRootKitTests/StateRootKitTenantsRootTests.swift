import XCTest
@testable import StateRootKit

final class StateRootKitTenantsRootTests: XCTestCase {
    func testInsideTenantRootReusesTenantsDirectory() {
        let root = StateRootKit.tenantsRoot(
            environment: ["SWIFT_APP_STATE_ROOT": "/Users/x/.tenants/personal"],
            homeDirectory: "/Users/x"
        )
        XCTAssertEqual(root, "/Users/x/.tenants")
    }

    func testInsideRoomFolderClimbsToTenantsDirectory() {
        let root = StateRootKit.tenantsRoot(
            environment: ["SWIFT_APP_STATE_ROOT": "/Users/x/.tenants/gujo/rooms/L1/seller/state"],
            homeDirectory: "/Users/x"
        )
        XCTAssertEqual(root, "/Users/x/.tenants")
    }

    func testOutsideRootNestsTenantsDirectory() {
        let root = StateRootKit.tenantsRoot(
            environment: ["SWIFT_APP_STATE_ROOT": "/tmp/isolated"],
            homeDirectory: "/Users/x"
        )
        XCTAssertEqual(root, "/tmp/isolated/.tenants")
        XCTAssertEqual(
            StateRootKit.tenantStateRoot(
                tenant: "tenant:gujo",
                environment: ["SWIFT_APP_STATE_ROOT": "/Users/x/.tenants/personal"],
                homeDirectory: "/Users/x"
            ),
            "/Users/x/.tenants/gujo"
        )
    }
}
