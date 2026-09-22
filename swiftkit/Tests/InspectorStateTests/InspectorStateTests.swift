import XCTest
@testable import InspectorState

final class InspectorStateTests: XCTestCase {
    func testSnapshotRoundTrips() throws {
        let snapshot = InspectorSnapshot(
            element: .init(
                name: "SaveButton", kind: "Button", selector: "Actions > SaveButton",
                source: "ShowcaseView.swift:86", frame: [79, 282, 39, 20],
                values: ["name": "홍길동", "canSave": "true"]),
            screenshotPath: "/tmp/inspector-SaveButton-86.png",
            logs: ["[error] Save failed — name is empty", "[info] Saved — name=demo"],
            promptContext: "```\nelement:  SaveButton (Button)\n```",
            timestamp: 1_720_000_000)

        let data = try JSONEncoder().encode(snapshot)
        let back = try JSONDecoder().decode(InspectorSnapshot.self, from: data)

        XCTAssertEqual(back.element.name, "SaveButton")
        XCTAssertEqual(back.element.source, "ShowcaseView.swift:86")
        XCTAssertEqual(back.element.frame, [79, 282, 39, 20])
        XCTAssertEqual(back.logs, ["[error] Save failed — name is empty", "[info] Saved — name=demo"])
        XCTAssertEqual(back.screenshotPath, "/tmp/inspector-SaveButton-86.png")
        XCTAssertEqual(back.promptContext, "```\nelement:  SaveButton (Button)\n```")
        XCTAssertEqual(back.element.values, ["name": "홍길동", "canSave": "true"])
    }

    func testStoreFileURLIsStableAndNamespaced() {
        let path = InspectorStateStore.fileURL.path
        XCTAssertTrue(path.hasSuffix("InspectorKit/last-pick.json"), path)
    }
}
