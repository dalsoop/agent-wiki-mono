import XCTest
import AppScaffoldKit
@testable import AgentWikiSynchronizerCore

final class SmokeTests: XCTestCase {
    func testAppFormContractCompliance() {
        XCTAssertTrue(RanodeAppFormContract.assertConforms(slug: "agent-wiki-global"))
    }
}
