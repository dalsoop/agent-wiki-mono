import XCTest
import GameSimulationStateKit
import GameSimulationReducerKit
@testable import GameSimulationRuntimeKit

/// Spine adoption without ECS: array-based domain state conforming only to
/// `GameSimulationBaseState` must still drive reducer, machine and snapshots.
final class GameSimulationEntityFreeStateTests: XCTestCase {
    private struct LedgerState: GameSimulationRuntimeParityState {
        static let schemaVersion = 3
        var simulationRevision: Int64 = 0
        var simulationTick: GameSimulationTick = 0
        var resources: [Int] = [0, 0]
        var log: [String] = []
    }

    private enum Action: Codable, Equatable, Sendable {
        case grant(Int)
    }

    private struct Reducer: GameSimulationReducer {
        func reduceTick(
            state: inout LedgerState,
            tick: GameSimulationTick,
            environment: Void
        ) throws -> GameSimulationEffect<Action> {
            state.simulationTick = tick
            state.simulationRevision += 1
            state.resources[0] += 1
            return .none
        }

        func reduceAction(
            state: inout LedgerState,
            action: Action,
            environment: Void
        ) throws -> GameSimulationEffect<Action> {
            switch action {
            case .grant(let amount):
                state.resources[1] += amount
                state.log.append("grant-\(amount)")
            }
            state.simulationRevision += 1
            return .none
        }
    }

    func testEntityFreeStateRunsMachineAndSnapshotRoundTrip() throws {
        var machine = GameSimulationMachine(
            parityState: LedgerState(),
            environment: (),
            reducer: Reducer()
        )
        try machine.send(.grant(5))
        try machine.advance(ticks: 3)

        XCTAssertEqual(machine.state.resources, [3, 5])
        XCTAssertEqual(machine.currentTick, 3)
        XCTAssertEqual(machine.revision, 4)

        let data = try machine.snapshotData()
        var restored = GameSimulationMachine(
            parityState: LedgerState(),
            environment: (),
            reducer: Reducer()
        )
        try restored.restoreSnapshot(from: data)
        XCTAssertEqual(restored.state, machine.state)
        XCTAssertEqual(restored.revision, machine.revision)
        XCTAssertEqual(restored.currentTick, machine.currentTick)
    }

    func testEntitySystemActionFailsOnEntityFreeState() throws {
        var machine = GameSimulationMachine(
            parityState: LedgerState(),
            environment: (),
            reducer: Reducer()
        )
        let before = machine.state
        XCTAssertThrowsError(
            try machine.sendSystemAction(.addEntity(GameEntityRecord(id: "a")))
        ) { error in
            XCTAssertEqual(
                error as? GameSimulationExecutionError,
                .entitiesUnsupported
            )
        }
        XCTAssertEqual(machine.state, before)
        XCTAssertEqual(machine.revision, 0)
    }
}
