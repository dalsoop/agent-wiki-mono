import XCTest
@testable import RoomSeatKit
@testable import RoomKit

final class RoomWindowDAGTests: XCTestCase {

    func testWindowDAGTopologicalOrder() {
        // D0 (Root), D1 (Child Tools), D2 (Inspectors/Modals)
        let wD0 = WindowIdentity(
            cgWindowID: 100,
            pid: 1001,
            roomID: "room-alpha",
            bundleID: "com.microsoft.VSCode",
            title: "VSCode - Project",
            depth: 0,
            appRole: .primary
        )

        let wD1_terminal = WindowIdentity(
            cgWindowID: 101,
            pid: 1001,
            roomID: "room-alpha",
            bundleID: "com.microsoft.VSCode",
            title: "Integrated Terminal",
            depth: 1,
            parentWindowID: 100,
            appRole: .childTool
        )

        let wD1_browser = WindowIdentity(
            cgWindowID: 200,
            pid: 2001,
            roomID: "room-alpha",
            bundleID: "net.ranode.agent-browser",
            title: "Localhost Preview",
            depth: 1,
            parentWindowID: 100,
            appRole: .childTool
        )

        let wD2_inspector = WindowIdentity(
            cgWindowID: 201,
            pid: 2001,
            roomID: "room-alpha",
            bundleID: "net.ranode.agent-browser",
            title: "DevTools Inspector",
            depth: 2,
            parentWindowID: 200,
            appRole: .inspector
        )

        // 무작위 순서로 DAG 구성
        let dag = WindowDAG(windows: [wD2_inspector, wD0, wD1_browser, wD1_terminal])

        // 1. 위상 정렬 검증 (D0 -> D1 -> D2 순서로 활성화)
        let order = dag.topologicalOrder()
        XCTAssertEqual(order.count, 4)
        XCTAssertEqual(order[0].depth, 0)
        XCTAssertEqual(order[0].cgWindowID, 100)
        XCTAssertEqual(order[1].depth, 1)
        XCTAssertEqual(order[2].depth, 1)
        XCTAssertEqual(order[3].depth, 2)
        XCTAssertEqual(order[3].cgWindowID, 201)

        // 2. 역위상 정렬 검증 (D2 -> D1 -> D0 순서로 연쇄 은닉)
        let reverseOrder = dag.reverseTopologicalOrder()
        XCTAssertEqual(reverseOrder.count, 4)
        XCTAssertEqual(reverseOrder[0].depth, 2)
        XCTAssertEqual(reverseOrder[0].cgWindowID, 201)
        XCTAssertEqual(reverseOrder[1].depth, 1)
        XCTAssertEqual(reverseOrder[2].depth, 1)
        XCTAssertEqual(reverseOrder[3].depth, 0)
        XCTAssertEqual(reverseOrder[3].cgWindowID, 100)
    }

    func testSubtreeAndSoloCapability() {
        let root = WindowIdentity(
            cgWindowID: 500,
            pid: 5000,
            roomID: "room-dev",
            bundleID: "com.apple.dt.Xcode",
            title: "Workspace",
            depth: 0
        )
        let child1 = WindowIdentity(
            cgWindowID: 501,
            pid: 5000,
            roomID: "room-dev",
            bundleID: "com.apple.dt.Xcode",
            title: "Assistant Editor",
            depth: 1,
            parentWindowID: 500
        )
        let leaf = WindowIdentity(
            cgWindowID: 502,
            pid: 5000,
            roomID: "room-dev",
            bundleID: "com.apple.dt.Xcode",
            title: "Memory Debugger",
            depth: 2,
            parentWindowID: 501
        )
        let standalone = WindowIdentity(
            cgWindowID: 600,
            pid: 6000,
            roomID: "room-dev",
            bundleID: "com.googlecode.iterm2",
            title: "Standalone Shell",
            depth: 0
        )

        let dag = WindowDAG(windows: [root, child1, leaf, standalone])

        // Xcode 서브트리 조회 -> child1, leaf 두 개가 포함되어야 함
        let sub = dag.subtree(for: 500)
        XCTAssertEqual(sub.count, 2)
        XCTAssertTrue(sub.contains(where: { $0.cgWindowID == 501 }))
        XCTAssertTrue(sub.contains(where: { $0.cgWindowID == 502 }))

        // D0 Solo 지원 여부
        XCTAssertTrue(dag.isSoloCapable(for: 500))
        XCTAssertFalse(dag.isSoloCapable(for: 600)) // 서브트리 없는 단독 창
    }

    func testStrictBaselinePolicyAndWindowScope() {
        let sticky = WindowIdentity(
            cgWindowID: 10,
            pid: 100,
            roomID: "global",
            bundleID: "com.tinyspeck.slackmacgap",
            title: "Slack",
            scope: .globalSticky
        )
        let roomWin = WindowIdentity(
            cgWindowID: 20,
            pid: 200,
            roomID: "room-alpha",
            bundleID: "com.microsoft.VSCode",
            title: "VSCode",
            scope: .roomSpecific
        )

        XCTAssertEqual(sticky.scope, .globalSticky)
        XCTAssertEqual(roomWin.scope, .roomSpecific)

        let policy = RoomWindowPolicy.default
        XCTAssertEqual(policy.mode, .strictBaseline)
        XCTAssertTrue(policy.autoFocusOnEnter)
        XCTAssertEqual(policy.deactivationAction, .hide)
    }
}
