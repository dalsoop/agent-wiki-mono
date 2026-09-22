import XCTest
import GameSimulationStateKit
import GameSimulationReducerKit
import GameSimulationProtocolKit
@testable import GameSimulationRuntimeKit

final class GameSimulationDocumentationExampleTests: XCTestCase {
    private struct Health: GameSimulationComponent {
        static let componentID = "health"
        var entityID: GameEntityID
        var value: Int

        init(entityID: GameEntityID) {
            self.entityID = entityID
            value = 100
        }
    }

    private struct KingdomState: GameSimulationState {
        static let schemaVersion = 1
        var entities = GameEntityRepository()
        var health: [GameEntityID: Health] = [:]
        var food = 0
    }

    private enum KingdomAction: Codable, Equatable, Sendable {
        case harvest
    }

    private struct KingdomReducer: GameSimulationReducer, Sendable {
        func reduceAction(
            state: inout KingdomState,
            action: KingdomAction,
            environment: Void
        ) -> GameSimulationEffect<KingdomAction> {
            state.food += 1
            return .none
        }
    }

    private func makeComponents() throws -> GameComponentRegistry<KingdomState> {
        var components = GameComponentRegistry<KingdomState>()
        try components.register(.init(Health.self, at: \KingdomState.health))
        return components
    }

    func testDocumentedRuntimeAndSnapshotFlowCompilesAndRuns() async throws {
        var state = KingdomState()
        try state.entities.add(.init(id: "hero", tags: ["ruler"]))
        state.health["hero"] = Health(entityID: "hero")
        let runtime = GameSimulationRuntime(
            machine: try .init(
                state: state,
                environment: (),
                reducer: KingdomReducer(),
                configuration: .init(
                    componentRegistry: try makeComponents(),
                    seed: 42
                )
            ),
            protocolVersion: 1
        )
        let session = try await runtime.connect(.init(
            protocolVersion: 1,
            clientKind: .ui,
            clientVersion: "1.0.0"
        ))
        let harvest = await runtime.submit(
            .init(
                commandID: "harvest-1",
                expectedRevision: 0,
                payload: .dispatch(.harvest)
            ),
            sessionID: session
        )
        let snapshot = await runtime.submit(
            .init(
                commandID: "snapshot-1",
                expectedRevision: harvest.result.revision,
                payload: .requestSnapshot
            ),
            sessionID: session
        )

        var restored = try GameSimulationMachine(
            state: KingdomState(),
            environment: (),
            reducer: KingdomReducer(),
            configuration: .init(componentRegistry: try makeComponents())
        )
        try restored.restoreSnapshot(from: XCTUnwrap(snapshot.snapshotData))

        XCTAssertEqual(restored.state.food, 1)
        XCTAssertEqual(restored.state.health["hero"]?.value, 100)
    }
}
