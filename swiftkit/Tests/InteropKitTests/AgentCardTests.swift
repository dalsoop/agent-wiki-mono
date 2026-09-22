import XCTest
@testable import InteropKit

final class AgentCardTests: XCTestCase {
    private func sampleCapabilities() -> Capabilities {
        Capabilities(
            name: "Test App",
            version: "1.0.0",
            cli: "test-app",
            commands: [.init(name: "status", summary: "상태", json: true)],
            state: [.init(path: "~/.test/state.json", what: "현재 상태")],
            health: .init(command: "test-app status", freshness: "~/.test/state.json")
        )
    }

    // MARK: - 직렬화

    func testRoundTrip() throws {
        let card = AgentCard(
            source: .app,
            provider: .init(slug: "test-app", name: "Test App", version: "1.0.0", description: "설명"),
            capabilities: sampleCapabilities(),
            skills: [.init(id: "s1", name: "스킬", description: "d", doc: "cli://test-app skill show s1")],
            interfaces: [.init(protocolBinding: "cli", target: "test-app")],
            extensions: [.init(id: "todo", uri: "cli://test-app todo --json")]
        )
        let data = try JSONEncoder().encode(card)
        let back = try JSONDecoder().decode(AgentCard.self, from: data)
        XCTAssertEqual(back, card)
    }

    /// 카드가 자라도 옛 소비자가 안 깨져야 한다 — A2A·MCP 가 공통으로 요구하는 규칙.
    func testUnknownFieldsAreIgnored() throws {
        let json = """
        {
          "specVersion": "1.0",
          "source": "app",
          "provider": {"slug": "x", "name": "X"},
          "futureField": {"anything": [1, 2, 3]},
          "anotherOne": "ignored"
        }
        """
        let card = try JSONDecoder().decode(AgentCard.self, from: Data(json.utf8))
        XCTAssertEqual(card.provider.slug, "x")
        XCTAssertEqual(card.source, .app)
    }

    /// 최소 카드 — fallback 이 낼 수 있는 가장 얇은 형태가 유효해야 한다.
    func testMinimalCardDecodes() throws {
        let json = """
        {"specVersion":"1.0","source":"fallback","provider":{"slug":"y","name":"Y"}}
        """
        let card = try JSONDecoder().decode(AgentCard.self, from: Data(json.utf8))
        XCTAssertNil(card.capabilities)
        XCTAssertNil(card.skills)
        XCTAssertFalse(card.hasCapabilityDetail)
    }

    // MARK: - source

    func testSourceRawValues() {
        // 에이전트가 문자열로 분기하므로 값이 바뀌면 안 된다.
        XCTAssertEqual(AgentCard.Source.app.rawValue, "app")
        XCTAssertEqual(AgentCard.Source.registry.rawValue, "registry")
        XCTAssertEqual(AgentCard.Source.fallback.rawValue, "fallback")
    }

    // MARK: - 파생 프로퍼티

    func testHasCapabilityDetailDistinguishesFallback() {
        let rich = AgentCard(source: .app, provider: .init(slug: "a", name: "A"),
                             capabilities: sampleCapabilities())
        XCTAssertTrue(rich.hasCapabilityDetail, "명령이 있으면 실제 능력 정보다")

        let empty = Capabilities(name: "A", version: "1", cli: "a", commands: [],
                                 state: [], health: .init(command: "", freshness: ""))
        let thin = AgentCard(source: .fallback, provider: .init(slug: "a", name: "A"),
                             capabilities: empty)
        XCTAssertFalse(thin.hasCapabilityDetail, "명령이 비면 조립된 껍데기다")
    }

    func testCLICommandNames() {
        let card = AgentCard(source: .app, provider: .init(slug: "a", name: "A"),
                             capabilities: sampleCapabilities())
        XCTAssertEqual(card.cliCommandNames, ["status"])

        let none = AgentCard(source: .fallback, provider: .init(slug: "a", name: "A"))
        XCTAssertEqual(none.cliCommandNames, [], "capabilities 가 없으면 빈 배열")
    }

    // MARK: - Envelope 결합

    /// 카드는 기존 봉투에 그대로 실려야 한다 — 37개 앱이 쓰는 형식과 같아야 소비자가 하나다.
    func testCardFitsInEnvelope() throws {
        let card = AgentCard(source: .app, provider: .init(slug: "a", name: "A"))
        let data = try JSONEncoder().encode(Envelope.Success(result: card))
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(obj?["ok"] as? Bool, true)
        XCTAssertNotNil(obj?["result"])
    }
}
