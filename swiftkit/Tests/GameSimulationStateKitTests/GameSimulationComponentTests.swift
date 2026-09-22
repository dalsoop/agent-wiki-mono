import XCTest
@testable import GameSimulationStateKit

final class GameSimulationComponentTests: XCTestCase {
    private struct Health: GameSimulationComponent {
        static let componentID = "health"
        var entityID: GameEntityID
        var value: Int

        init(entityID: GameEntityID) {
            self.entityID = entityID
            value = 100
        }
    }

    private struct TestState: GameSimulationState {
        static let schemaVersion = 1
        var entities = GameEntityRepository()
        var health: [GameEntityID: Health] = [:]
        var cleanupLog: [String] = []
    }

    func testRegisteredCleanupRemovesComponentAndDuplicateIDIsRejected() throws {
        var state = TestState()
        state.health["hero"] = Health(entityID: "hero")
        var registry = GameComponentRegistry<TestState>()
        try registry.register(.init(Health.self, at: \TestState.health))

        XCTAssertThrowsError(try registry.register(.init(Health.self, at: \TestState.health))) {
            XCTAssertEqual($0 as? GameComponentRegistryError, .duplicateComponentID("health"))
        }
        registry.removeAll(for: "hero", from: &state)
        XCTAssertNil(state.health["hero"])
    }

    func testCleanupUsesStableComponentIDOrder() throws {
        var state = TestState()
        var registry = GameComponentRegistry<TestState>()
        try registry.register(.init(componentID: "zeta") { _, state in state.cleanupLog.append("zeta") })
        try registry.register(.init(componentID: "alpha") { _, state in state.cleanupLog.append("alpha") })

        registry.removeAll(for: "hero", from: &state)

        XCTAssertEqual(state.cleanupLog, ["alpha", "zeta"])
        XCTAssertEqual(registry.componentIDs, ["alpha", "zeta"])
    }

    func testEmptyComponentIDIsRejected() {
        var registry = GameComponentRegistry<TestState>()
        XCTAssertThrowsError(
            try registry.register(.init(componentID: "") { _, _ in })
        ) {
            XCTAssertEqual($0 as? GameComponentRegistryError, .emptyComponentID)
        }
    }

    func testComponentStateCodableRoundTrip() throws {
        var state = TestState()
        state.health["hero"] = Health(entityID: "hero")

        let decoded = try JSONDecoder().decode(
            TestState.self,
            from: JSONEncoder().encode(state)
        )

        XCTAssertEqual(decoded, state)
        XCTAssertEqual(decoded.health["hero"]?.value, 100)
    }

    /// 레지스트리는 액터 간에 건네지는 값이다 — 참조로 새면 한 시뮬레이션의 등록이
    /// 다른 쪽 사본에 나타나 결정성이 깨진다. Sendable 은 컴파일 타임에, 값 의미론은
    /// 여기서 실측으로 고정한다.
    func testRegistryIsAValueSoCopiesDoNotSeeLaterRegistrations() throws {
        let registration = GameComponentRegistration<TestState>(
            Health.self,
            at: \TestState.health
        )
        var registry = GameComponentRegistry<TestState>()
        try registry.register(registration)

        let copy = registry
        try registry.register(.init(componentID: "later") { _, _ in })

        XCTAssertEqual(copy.componentIDs, ["health"], "사본이 나중 등록을 보면 값이 아니라 참조다")
        XCTAssertEqual(registry.componentIDs, ["health", "later"])

        var stateFromCopy = TestState()
        stateFromCopy.health["hero"] = Health(entityID: "hero")
        copy.removeAll(for: "hero", from: &stateFromCopy)
        XCTAssertNil(stateFromCopy.health["hero"], "사본도 자기가 아는 등록으로 정리는 해야 한다")

        requireSendable(registration)
        requireSendable(registry)
    }

    private func requireSendable<Value: Sendable>(_ value: Value) {}
}
