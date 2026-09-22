import XCTest
import StateRootKit
@testable import OrganKit

final class BorrowedStateRootTests: XCTestCase {
    private func borrow(_ env: [String: String]) -> BorrowedStateRoot {
        BorrowedStateRoot(inheriting: env, resolvedBy: { $0[StateRootKit.declaredEnv] ?? "/home/x" })
    }

    func testAdapterCannotSetStateRoot() {
        let root = borrow(["PATH": "/usr/bin"])
        XCTAssertThrowsError(
            try root.childEnvironment(adding: [StateRootKit.declaredEnv: "/tmp/hijack"])
        ) { err in
            XCTAssertEqual(err as? BorrowedStateRoot.Refusal,
                           .mutatesStateRoot(key: StateRootKit.declaredEnv))
        }
    }

    func testRefusalSaysWhoDecidesTheRoot() {
        let reason = BorrowedStateRoot.Refusal.mutatesStateRoot(key: "SWIFT_APP_STATE_ROOT")
        XCTAssertTrue(reason.description.contains("StateRootKit"),
                      "거절 사유가 루트를 정하는 주체를 말해야 한다: \(reason.description)")
    }

    func testInheritedStateRootPassesThroughUntouched() throws {
        let root = borrow([StateRootKit.declaredEnv: "/tenants/wife", "PATH": "/usr/bin"])
        XCTAssertEqual(root.path, "/tenants/wife")
        let child = try root.childEnvironment(adding: ["TENANT_ID": "tenant:wife"])
        XCTAssertEqual(child[StateRootKit.declaredEnv], "/tenants/wife",
                       "상속된 루트는 그대로 자식에게 간다")
        XCTAssertEqual(child["TENANT_ID"], "tenant:wife")
        XCTAssertEqual(child["PATH"], "/usr/bin")
    }

    func testOtherKeysAreStillAddable() throws {
        let child = try borrow(["PATH": "/usr/bin"])
            .childEnvironment(adding: ["ROOM_ID": "r1", "TENANT_ID": "host"])
        XCTAssertEqual(child["ROOM_ID"], "r1")
        XCTAssertEqual(child["TENANT_ID"], "host")
    }

    func testReadsDoNotExposeAMutableEnvironment() {
        let root = borrow(["PATH": "/usr/bin"])
        XCTAssertEqual(root.value(forKey: "PATH"), "/usr/bin")
        XCTAssertNil(root.value(forKey: "NOPE"))
        XCTAssertTrue(root.hasKey("PATH"))
        XCTAssertFalse(root.hasKey(StateRootKit.declaredEnv))
    }

    func testEmptyExtrasStillYieldsTheInheritedEnvironment() throws {
        let child = try borrow(["PATH": "/usr/bin", "HOME": "/h"]).childEnvironment()
        XCTAssertEqual(child, ["PATH": "/usr/bin", "HOME": "/h"])
    }
}
