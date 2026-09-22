#if canImport(AppKit) && canImport(SwiftUI)
import XCTest
import SwiftUI
@testable import AppWindowKit

final class StandardWindowTests: XCTestCase {
    @MainActor
    func testStandardWindowDelegateReopenDefaults() {
        let delegate = StandardWindowAppDelegate()
        XCTAssertTrue(delegate.restoresHiddenWindowsOnReopen)
        
        let app = NSApplication.shared
        let handled = delegate.applicationShouldHandleReopen(app, hasVisibleWindows: true)
        XCTAssertTrue(handled)
    }

    @MainActor
    func testStandardWindowViewModifierApplication() {
        let view = Text("Hello World")
            .standardWindow(
                title: "Test Window",
                minSize: CGSize(width: 640, height: 480),
                defaultSize: CGSize(width: 800, height: 600),
                autosaveKey: "TestWindowAutosaveKey",
                preventsClose: true,
                standardToolbar: true,
                bringToFront: false,
                colorScheme: .dark
            )
        XCTAssertNotNil(view)
    }

    @MainActor
    func testStandardWindowWithFooterApplication() {
        let view = Text("Main Content")
            .standardWindow(
                title: "Window with Footer",
                minSize: CGSize(width: 700, height: 500),
                autosaveKey: "WindowWithFooterKey",
                preventsClose: false
            ) {
                Text("Footer Bar")
            }
        XCTAssertNotNil(view)
    }

    @MainActor
    func testStandardWindowSceneInstantiation() {
        let scene = StandardWindow(
            title: "Scene Title",
            id: "test-window",
            minSize: CGSize(width: 800, height: 600),
            defaultSize: CGSize(width: 1024, height: 768),
            autosaveKey: "SceneAutosaveKey",
            preventsClose: true,
            standardToolbar: true,
            colorScheme: .light
        ) {
            Text("Scene Content")
        }
        XCTAssertEqual(scene.title, "Scene Title")
        XCTAssertEqual(scene.id, "test-window")
        XCTAssertEqual(scene.minSize, CGSize(width: 800, height: 600))
        XCTAssertEqual(scene.defaultSize, CGSize(width: 1024, height: 768))
        XCTAssertEqual(scene.autosaveKey, "SceneAutosaveKey")
        XCTAssertTrue(scene.preventsClose)
        XCTAssertTrue(scene.standardToolbar)
        XCTAssertEqual(scene.colorScheme, .light)
    }

    @MainActor
    func testStandardWindowSceneWithFooterInstantiation() {
        let scene = StandardWindow(
            "Positional Title",
            minSize: CGSize(width: 600, height: 400),
            autosaveKey: "PositionalAutosaveKey"
        ) {
            Text("Footer")
        } content: {
            Text("Content")
        }
        XCTAssertEqual(scene.title, "Positional Title")
        XCTAssertEqual(scene.minSize, CGSize(width: 600, height: 400))
        XCTAssertEqual(scene.autosaveKey, "PositionalAutosaveKey")
    }
}
#endif
