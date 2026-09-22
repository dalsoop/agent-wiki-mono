#if canImport(AppKit) && canImport(SwiftUI)
import XCTest
import SwiftUI
@testable import AppWindowKit

final class ScaffoldFooterBarTests: XCTestCase {
    @MainActor
    func testScaffoldFooterBarModifierCanBeApplied() {
        let view = Text("Hello World")
            .scaffoldFooterBar {
                Text("Footer Content")
            }
        XCTAssertNotNil(view)
    }
}
#endif
