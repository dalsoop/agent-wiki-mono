import XCTest
import AppScaffoldKit
@testable import AgentWikiIndexerCore

final class SmokeTests: XCTestCase {
    func testAppFormContractCompliance() {
        XCTAssertTrue(RanodeAppFormContract.assertConforms(slug: "agent-wiki-local"))
    }
}
