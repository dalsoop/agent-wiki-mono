import XCTest

@testable import GameUIRuntimeKit

final class GameUIRuntimeKitModuleSmokeTests: XCTestCase {
  func testSchemaVersionMatchesAssetKit() {
    XCTAssertEqual(GameUIRuntimeKit.schemaVersion, 1)
  }
}
