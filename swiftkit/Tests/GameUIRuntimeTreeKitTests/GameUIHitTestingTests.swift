import XCTest
@testable import GameUIRuntimeTreeKit

final class GameUIHitTestingTests: XCTestCase {
    func testTopmostChildWinsAndSharedEdgeIsHalfOpen() {
        let root = node(
            "root",
            frame: .init(x: 0, y: 0, width: 200, height: 100),
            children: [
                button("left", x: 0, width: 100, z: 0),
                button("right", x: 100, width: 100, z: 1),
                button("overlay", x: 50, width: 100, z: 2),
            ]
        )

        XCTAssertEqual(root.hitTest(.init(x: 75, y: 50))?.identity, ["root", "overlay"])
        XCTAssertEqual(root.hitTest(.init(x: 100, y: 50))?.identity, ["root", "overlay"])
        XCTAssertEqual(root.hitTest(.init(x: 199.999, y: 50))?.identity, ["root", "right"])
        XCTAssertNil(root.hitTest(.init(x: 200, y: 50)))
    }

    func testDeepestInteractiveChildWinsOverParent() {
        let child = button("child", x: 20, width: 60, z: 0)
        let parent = GameUIRuntimeNode(
            id: "parent",
            layout: .init(frame: .init(x: 0, y: 0, width: 100, height: 100)),
            interaction: .init(upActionID: "parent"),
            children: [child]
        )

        XCTAssertEqual(parent.hitTest(.init(x: 30, y: 50))?.actionID, "child")
        XCTAssertEqual(parent.hitTest(.init(x: 90, y: 50))?.actionID, "parent")
    }

    func testHiddenDisabledAndClippedSubtreesDoNotHit() {
        let hidden = GameUIRuntimeNode(
            id: "hidden",
            layout: .init(frame: .init(x: 0, y: 0, width: 50, height: 50)),
            appearance: .init(isVisible: false),
            interaction: .init(upActionID: "hidden")
        )
        let disabled = GameUIRuntimeNode(
            id: "disabled",
            layout: .init(frame: .init(x: 50, y: 0, width: 50, height: 50)),
            appearance: .init(isEnabled: false),
            interaction: .init(upActionID: "disabled")
        )
        let clipped = GameUIRuntimeNode(
            id: "clip",
            layout: .init(
                frame: .init(x: 100, y: 0, width: 100, height: 100),
                clipRect: .init(x: 0, y: 0, width: 20, height: 20)
            ),
            children: [button("outside", x: 30, width: 40, z: 0)]
        )
        let root = node(
            "root",
            frame: .init(x: 0, y: 0, width: 200, height: 100),
            children: [hidden, disabled, clipped]
        )

        XCTAssertNil(root.hitTest(.init(x: 10, y: 10)))
        XCTAssertNil(root.hitTest(.init(x: 60, y: 10)))
        XCTAssertNil(root.hitTest(.init(x: 140, y: 50)))
    }

    func testModalBarrierBlocksUnderlyingButton() {
        let underlying = button("underlying", x: 0, width: 200, z: 0)
        let modalBarrier = GameUIRuntimeNode(
            id: "modal-barrier",
            layout: .init(
                frame: .init(x: 0, y: 0, width: 200, height: 100),
                zIndex: 10
            ),
            appearance: .init(blocksLowerLayers: true)
        )
        let root = node(
            "root",
            frame: .init(x: 0, y: 0, width: 200, height: 100),
            children: [underlying, modalBarrier]
        )

        let result = root.hitTest(.init(x: 20, y: 20))
        XCTAssertEqual(result?.disposition, .blocked)
        XCTAssertEqual(result?.identity, ["root", "modal-barrier"])
        XCTAssertNil(result?.actionID)
    }

    func testBackdropActionCanExplicitlyDismissModal() {
        let backdrop = GameUIRuntimeNode(
            id: "backdrop",
            layout: .init(
                frame: .init(x: 0, y: 0, width: 200, height: 100),
                zIndex: 10
            ),
            appearance: .init(blocksLowerLayers: true),
            interaction: .init(upActionID: "dismiss")
        )
        let root = node(
            "root",
            frame: .init(x: 0, y: 0, width: 200, height: 100),
            children: [button("underlying", x: 0, width: 200, z: 0), backdrop]
        )

        let result = root.hitTest(.init(x: 20, y: 20))
        XCTAssertEqual(result?.disposition, .hit)
        XCTAssertEqual(result?.actionID, "dismiss")
    }

    func testCodableTreeKeepsRepeatedIdentityAcrossReorder() throws {
        let before = repeatedFixture(ids: ["a", "b"])
        let after = repeatedFixture(ids: ["b", "a"])

        XCTAssertEqual(
            before.identityPath(forNodeID: "item", repeatedKey: "a"),
            after.identityPath(forNodeID: "item", repeatedKey: "a")
        )
        let decoded = try JSONDecoder().decode(
            GameUIRuntimeNode.self,
            from: JSONEncoder().encode(after)
        )
        XCTAssertEqual(decoded, after)
    }

    func testCoordinateSpaceAndLayerAreDataNotRendererState() {
        let node = GameUIRuntimeNode(
            id: "health",
            layout: .init(
                frame: .init(x: 0, y: 0, width: 100, height: 10),
                coordinateSpace: .world,
                layerID: "unit-overlay",
                zIndex: 4
            )
        )
        XCTAssertEqual(node.coordinateSpace, .world)
        XCTAssertEqual(node.layerID, "unit-overlay")
        XCTAssertEqual(node.zIndex, 4)
    }

    func testRepeatedIdentityCombinesNodeIDAndRepeatedKey() {
        let root = GameUIRuntimeNode(
            id: "root",
            layout: .init(frame: .init(x: 0, y: 0, width: 200, height: 100)),
            children: [
                GameUIRuntimeNode(
                    id: "primary",
                    repeatedKey: "shared",
                    layout: .init(frame: .init(x: 0, y: 0, width: 100, height: 100))
                ),
                GameUIRuntimeNode(
                    id: "secondary",
                    repeatedKey: "shared",
                    layout: .init(frame: .init(x: 100, y: 0, width: 100, height: 100))
                ),
            ]
        )

        let primary = root.identityPath(forNodeID: "primary", repeatedKey: "shared")
        let secondary = root.identityPath(forNodeID: "secondary", repeatedKey: "shared")
        XCTAssertNotEqual(primary, secondary)
        XCTAssertEqual(
            primary?.tokens.last,
            GameUIIdentityToken(nodeID: "primary", repeatedKey: "shared")
        )
    }

    private func node(
        _ id: String,
        frame: GameUIRect,
        children: [GameUIRuntimeNode]
    ) -> GameUIRuntimeNode {
        GameUIRuntimeNode(id: id, layout: .init(frame: frame), children: children)
    }

    private func button(
        _ id: String,
        x: Double,
        width: Double,
        z: Int
    ) -> GameUIRuntimeNode {
        GameUIRuntimeNode(
            id: id,
            layout: .init(
                frame: .init(x: x, y: 0, width: width, height: 100),
                zIndex: z
            ),
            interaction: .init(upActionID: id)
        )
    }

    private func repeatedFixture(ids: [String]) -> GameUIRuntimeNode {
        GameUIRuntimeNode(
            id: "root",
            layout: .init(frame: .init(x: 0, y: 0, width: 200, height: 100)),
            children: ids.enumerated().map { index, key in
                GameUIRuntimeNode(
                    id: "item",
                    repeatedKey: key,
                    layout: .init(
                        frame: .init(x: Double(index * 50), y: 0, width: 50, height: 50)
                    )
                )
            }
        )
    }
}
