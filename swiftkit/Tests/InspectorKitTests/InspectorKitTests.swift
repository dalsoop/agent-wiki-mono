import XCTest
@testable import InspectorKit

final class InspectedElementTests: XCTestCase {
    func testSourceRefDropsModulePrefix() {
        let el = InspectedElement(name: "Save", file: "MyApp/SettingsView.swift", line: 42)
        XCTAssertEqual(el.fileBasename, "SettingsView.swift")
        XCTAssertEqual(el.sourceRef, "SettingsView.swift:42")
        XCTAssertEqual(el.id, "MyApp/SettingsView.swift:42")
    }

    func testPromptContextIsUnambiguousMarkdown() {
        let el = InspectedElement(
            name: "SaveButton", file: "MyApp/SettingsView.swift", line: 42,
            kind: "Button", selector: "Root > Settings > SaveButton",
            frame: CGRect(x: 20, y: 100, width: 120, height: 44))
        let ctx = el.promptContext()
        XCTAssertTrue(ctx.contains("element:  SaveButton (Button)"))
        XCTAssertTrue(ctx.contains("selector: Root > Settings > SaveButton"))
        XCTAssertTrue(ctx.contains("source:   SettingsView.swift:42"))
        XCTAssertTrue(ctx.contains("frame:    x=20 y=100 w=120 h=44"))
        XCTAssertFalse(ctx.contains("shot:"))  // no screenshot path passed
    }

    func testPromptContextIncludesScreenshotWhenGiven() {
        let el = InspectedElement(name: "X", file: "A/B.swift", line: 1)
        XCTAssertTrue(el.promptContext(screenshotPath: "/tmp/x.png").contains("shot:     /tmp/x.png"))
    }

    func testPromptContextToleratesEmptyOptionalFields() {
        let el = InspectedElement(name: "", file: "A/B.swift", line: 7)
        let ctx = el.promptContext()
        XCTAssertTrue(ctx.contains("element:  (unnamed)"))
        XCTAssertFalse(ctx.contains("selector:"))  // omitted when empty
    }

    func testPromptContextAppendsRecentLogs() {
        let el = InspectedElement(name: "SaveButton", file: "A/B.swift", line: 9)
        let ctx = el.promptContext(logs: ["[error] Save failed — name is empty", "[info] retry"])
        XCTAssertTrue(ctx.contains("recent logs:"))
        XCTAssertTrue(ctx.contains("[error] Save failed — name is empty"))
        XCTAssertTrue(ctx.contains("[info] retry"))
    }

    func testPromptContextNoLogSectionWhenEmpty() {
        let ctx = InspectedElement(name: "X", file: "A/B.swift", line: 1).promptContext()
        XCTAssertFalse(ctx.contains("recent logs:"))
    }

    func testPromptContextIncludesRuntimeValues() {
        let el = InspectedElement(
            name: "NameField", file: "A/B.swift", line: 5, kind: "TextField",
            values: ["text": "홍길동", "empty": "false"])
        let ctx = el.promptContext()
        XCTAssertTrue(ctx.contains("values:"))
        XCTAssertTrue(ctx.contains("text = 홍길동"))
        XCTAssertTrue(ctx.contains("empty = false"))
    }

    func testPromptContextNoValuesSectionWhenEmpty() {
        let ctx = InspectedElement(name: "X", file: "A/B.swift", line: 1).promptContext()
        XCTAssertFalse(ctx.contains("values:"))
    }

    func testTaggedElementShowsSourceRef() {
        let el = InspectedElement(name: "X", file: "App/B.swift", line: 5)  // .tagged default
        XCTAssertTrue(el.promptContext().contains("source:   B.swift:5"))
    }

    func testAccessibilityElementMarksUntagged() {
        let el = InspectedElement(
            name: "Save", file: "", line: 0, kind: "AXButton",
            selector: "(accessibility)", origin: .accessibility)
        let ctx = el.promptContext()
        XCTAssertTrue(ctx.contains("(untagged — accessibility only"))
        XCTAssertFalse(ctx.contains("source:   :0"))  // never the raw empty sourceRef
    }
}

@MainActor
final class InspectorHitTestTests: XCTestCase {
    private func makeController(_ els: [InspectedElement]) -> InspectorController {
        let c = InspectorController()
        c.elements = els
        return c
    }

    func testPicksMostSpecific_smallestContainingElement() {
        // A small button nested inside a large card; a point inside both must
        // resolve to the button, not the card.
        let card = InspectedElement(name: "Card", file: "A.swift", line: 1,
                                    frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        let button = InspectedElement(name: "Button", file: "A.swift", line: 2,
                                      frame: CGRect(x: 10, y: 10, width: 80, height: 40))
        let c = makeController([card, button])
        XCTAssertEqual(c.element(at: CGPoint(x: 20, y: 20))?.name, "Button")
        XCTAssertEqual(c.element(at: CGPoint(x: 200, y: 200))?.name, "Card")
    }

    func testMissReturnsNil() {
        let c = makeController([
            InspectedElement(name: "Card", file: "A.swift", line: 1,
                             frame: CGRect(x: 0, y: 0, width: 100, height: 100)),
        ])
        XCTAssertNil(c.element(at: CGPoint(x: 500, y: 500)))
    }

    func testZeroFrameElementsAreIgnored() {
        // Registered but not yet measured (frame == .zero) shouldn't swallow hits.
        let c = makeController([
            InspectedElement(name: "Unmeasured", file: "A.swift", line: 1, frame: .zero),
        ])
        XCTAssertNil(c.element(at: CGPoint(x: 0, y: 0)))
    }
}
