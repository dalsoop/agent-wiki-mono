import XCTest
@testable import GameUIAssetKit

final class GameUIAssetKitModuleSmokeTests: XCTestCase {
    func testSchemaVersionStartsAtOne() {
        XCTAssertEqual(GameUIAssetKit.schemaVersion, 1)
    }
}
