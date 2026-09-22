import XCTest
import AppScaffoldKit
@testable import AgentWikiGlobalCore

final class SmokeTests: XCTestCase {
    func testAppFormContractCompliance() {
        XCTAssertTrue(RanodeAppFormContract.assertConforms(slug: "agent-wiki-global"))
    }
}
