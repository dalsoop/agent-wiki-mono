import XCTest
@testable import AgentWikiStudioCore

final class DualEntryAdoptionTests: XCTestCase {
    func testIsSafeCLIRejectsMacOSGUIPath() {
        XCTAssertFalse(
            DualEntryAdoption.isSafeCLIExecutable(
                "/Applications/Agent Wiki.app/Contents/MacOS/KnowledgeBaseWiki"
            )
        )
    }

    func testIsSafeCLIRejectsMissing() {
        XCTAssertFalse(DualEntryAdoption.isSafeCLIExecutable("/tmp/no-such-agent-wiki-\(UUID().uuidString)"))
    }

    func testStatusChecklistKeysPresent() {
        let st = DualEntryAdoption.status()
        XCTAssertTrue(st.checklist.keys.contains("studio_app_present"))
        XCTAssertTrue(st.checklist.keys.contains("adopt_source_safe"))
        XCTAssertTrue(st.checklist.keys.contains("monlith_helper_safe"))
        XCTAssertTrue(st.checklist.keys.contains("studio_helper_agent_wiki"))
        XCTAssertTrue(st.checklist.keys.contains("path_agent_wiki_safe"))
        XCTAssertTrue(st.checklist.keys.contains("path_points_to_studio"))
    }

}
