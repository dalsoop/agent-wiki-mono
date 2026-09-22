import XCTest
import EndpointRouterKit
@testable import GujoStoreOpsCore

final class DeployPipelineTests: XCTestCase {
    func testStageStatusRawValues() {
        XCTAssertEqual(DeployStageStatus.ok.rawValue, "ok")
        XCTAssertEqual(DeployStageStatus.fail.rawValue, "fail")
    }

    func testSnapshotAllOkWhenNoFail() {
        let snap = DeploySnapshot(
            stages: [
                .init(id: "a", title: "A", detail: "x", status: .ok),
                .init(id: "b", title: "B", detail: "y", status: .skip),
            ],
            audit: [],
            opsBase: EndpointRouter.apps,
            summary: "test"
        )
        XCTAssertTrue(snap.allOk)
    }

    func testSnapshotNotAllOkOnFail() {
        let snap = DeploySnapshot(
            stages: [
                .init(id: "a", title: "A", detail: "x", status: .ok),
                .init(id: "b", title: "B", detail: "y", status: .fail),
            ],
            audit: [],
            opsBase: "https://x",
            summary: "t"
        )
        XCTAssertFalse(snap.allOk)
    }
}
