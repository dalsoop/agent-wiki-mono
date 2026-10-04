import Foundation
import Testing
@testable import KnowledgeBaseWikiCore

/// 접두어 없는 기본 작성자(`~/.config/citation-ledger/actor`)에 종류를 붙이는 규칙.
@Suite struct LawDefaultAuthorTests {
    @Test func bareNameInAgentSessionBecomesAgentOnThisDevice() {
        let env = ["CLAUDE_CODE_SESSION_ID": "s-1", "AI_AGENT": "claude-code_2.1"]
        #expect(LawActorResolution.qualified(author: "jeonghan", environment: env, device: "macbook")
            == "agent:claude-code@macbook")
    }

    @Test func bareNameWithoutAgentMarkerBecomesUser() {
        #expect(LawActorResolution.qualified(author: "jeonghan", environment: [:], device: "macbook") == "user:jeonghan")
    }

    @Test func prefixedAuthorIsKept() {
        let env = ["CLAUDE_CODE_SESSION_ID": "s-1"]
        #expect(LawActorResolution.qualified(author: "app:agent-wiki", environment: env, device: "macbook")
            == "app:agent-wiki")
        #expect(LawActorResolution.qualified(author: "user:jeonghan", environment: [:], device: nil) == "user:jeonghan")
    }

    @Test func qualifiedBareNameStillPassesHumanGate() throws {
        // 에이전트 세션에서 기본 작성자는 사람이 되지 않으므로 사람 위장 거부에 걸리지 않고 에이전트로 공포한다.
        let env = ["CLAUDE_CODE_SESSION_ID": "s-1"]
        let actor = try LawActorResolution.actor(
            author: "jeonghan",
            explicit: LawModelRecord(runtime: "claude-code", model: "claude-opus-5-5"),
            environment: env, device: "macbook",
            sessions: LawSessionRegistry(directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("law-default-author-\(UUID().uuidString)")))
        #expect(actor.kind == .agent)
        #expect(actor.author == "agent:claude-code@macbook")
    }
}
