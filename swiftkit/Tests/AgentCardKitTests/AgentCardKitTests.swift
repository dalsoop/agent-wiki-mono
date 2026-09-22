import XCTest
@testable import AgentCardKit
import AgentRegistryKit
import SkillRegistryKit

final class AgentCardKitTests: XCTestCase {

    func testAgentCardFields() {
        let def = AgentDef(
            identity: .init(id: "a1", name: "DB Helper", persona: "새벽"),
            runtime: .init(agent: "claude"),
            notes: "SQL 도움"
        )
        let card = AgentCard(def: def)
        XCTAssertEqual(card.cardID, "a1")
        XCTAssertEqual(card.title, "DB Helper")
        XCTAssertEqual(card.kind, .agent)
        XCTAssertEqual(card.tool, "claude")
        XCTAssertEqual(card.subtitle, "새벽")
        XCTAssertEqual(card.summary, "SQL 도움")
    }

    func testSkillCardFields() {
        let ref = SkillRef(id: "claude/wiki-record", name: "wiki-record", tool: "claude",
                           path: "/x/SKILL.md", scope: "global")
        let card = SkillCard(ref: ref)
        XCTAssertEqual(card.cardID, "claude/wiki-record")
        XCTAssertEqual(card.title, "wiki-record")
        XCTAssertEqual(card.kind, .skill)
        XCTAssertEqual(card.tool, "claude")
        XCTAssertEqual(card.path, "/x/SKILL.md")
        XCTAssertEqual(card.subtitle, "global")
    }

    func testCatalogCombinesAgentsAndWorkspaceSkills() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentcard-test-\(UUID().uuidString)")
        let skillDir = tmp.appendingPathComponent(".claude/skills/my-skill")
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        try "name: my-skill".write(to: skillDir.appendingPathComponent("SKILL.md"),
                                   atomically: true, encoding: .utf8)

        let agentsURL = tmp.appendingPathComponent("agents.json")
        let registry = AgentRegistry(url: agentsURL)
        try registry.save([AgentDef(identity: .init(id: "a1", name: "Helper"), runtime: .init(agent: "claude"))])

        let catalog = AppCardCatalog(appSlug: "testapp",
                                     workspaceRoot: tmp,
                                     agents: registry,
                                     skills: SkillRegistry(home: tmp, roots: []))  // global 비움
        let cards = catalog.cards()

        let agentCards = cards.filter { $0.kind == .agent }
        let skillCards = cards.filter { $0.kind == .skill }
        XCTAssertEqual(agentCards.count, 1)
        XCTAssertEqual(skillCards.count, 1)
        XCTAssertEqual(skillCards.first?.title, "my-skill")
        XCTAssertTrue(skillCards.first?.path?.hasSuffix("SKILL.md") ?? false)
    }

    func testScanWorkspaceSkillsSkipsDotAndUnderscore() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentcard-skip-\(UUID().uuidString)")
        for name in [".hidden", "_skip", "real"] {
            let d = tmp.appendingPathComponent(".claude/skills/\(name)")
            try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
            try "x".write(to: d.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        }
        let catalog = AppCardCatalog(appSlug: "t",
                                     workspaceRoot: tmp,
                                     agents: AgentRegistry(url: tmp.appendingPathComponent("a.json")),
                                     skills: SkillRegistry(home: tmp, roots: []))
        let skills = catalog.cards().filter { $0.kind == .skill }
        XCTAssertEqual(skills.count, 1)
        XCTAssertEqual(skills.first?.title, "real")
    }
}
