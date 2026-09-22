import XCTest
import GameSimulationStateKit
import GameSimulationReducerKit
@testable import GameSimulationRuntimeKit

final class GameSimulationMachineTests: XCTestCase {
    private struct Health: GameSimulationComponent {
        static let componentID = "health"
        var entityID: GameEntityID
        var value = 100
        init(entityID: GameEntityID) { self.entityID = entityID }
    }

    private struct State: GameSimulationState {
        static let schemaVersion = 1
        var entities = GameEntityRepository()
        var health: [GameEntityID: Health] = [:]
        var log: [String] = []
        var rejectTick = false
        var rejectEntityEvent = false
    }

    private struct ParityState: GameSimulationRuntimeParityState {
        static let schemaVersion = 1
        var entities = GameEntityRepository()
        var simulationRevision: Int64
        var simulationTick: GameSimulationTick
    }

    private struct ParityReducer: GameSimulationReducer {
        func reduceTick(
            state: inout ParityState,
            tick: GameSimulationTick,
            environment: Void
        ) throws -> GameSimulationEffect<Action> { .none }

        func reduceAction(
            state: inout ParityState,
            action: Action,
            environment: Void
        ) throws -> GameSimulationEffect<Action> { .none }
    }

    private enum Action: Codable, Equatable, Sendable {
        case start
        case first
        case second
        case reject
        case nestedReject
        case loop
        case schedule
        case due(String)
        case removeParent
    }

    private struct Reducer: GameSimulationReducer {
        func reduceTick(
            state: inout State,
            tick: GameSimulationTick,
            environment: Void
        ) throws -> GameSimulationEffect<Action> {
            if state.rejectTick {
                state.log.append("tick-will-rollback")
                throw TestRejection.rejected
            }
            return .none
        }

        func reduceAction(
            state: inout State,
            action: Action,
            environment: Void
        ) throws -> GameSimulationEffect<Action> {
            switch action {
            case .start:
                state.log.append("start")
                return .batch([.action(.first), .action(.second)])
            case .first:
                state.log.append("first")
                return .none
            case .second:
                state.log.append("second")
                return .none
            case .reject:
                state.log.append("will-rollback")
                throw TestRejection.rejected
            case .nestedReject:
                state.log.append("nested-start")
                return .batch([
                    .action(.first),
                    .action(.reject),
                    .action(.second),
                ])
            case .loop:
                state.log.append("loop")
                return .action(.loop)
            case .schedule:
                return .batch([
                    .scheduleAction(id: "b", at: 2, action: .due("b")),
                    .scheduleAction(id: "a", at: 2, action: .due("a")),
                    .scheduleAction(id: "cancelled", at: 2, action: .due("cancelled")),
                    .cancelScheduled(id: "cancelled"),
                ])
            case .due(let id):
                state.log.append("due:\(id)")
                return .none
            case .removeParent:
                return .system(.removeEntity("parent"))
            }
        }

        func reduceEntityEvent(
            state: inout State,
            event: GameSimulationEntityEvent,
            environment: Void
        ) throws -> GameSimulationEffect<Action> {
            if state.rejectEntityEvent {
                state.log.append("entity-will-rollback")
                throw TestRejection.rejected
            }
            switch event {
            case .added(let id): state.log.append("added:\(id.rawValue)")
            case .willRemove(let id): state.log.append("will:\(id.rawValue)")
            case .didRemove(let id): state.log.append("did:\(id.rawValue)")
            }
            return .none
        }
    }

    func testBatchAndNestedActionsRunFIFO() throws {
        var machine = try makeMachine(effectLimit: 16)
        try machine.send(.start)
        XCTAssertEqual(machine.state.log, ["start", "first", "second"])
        XCTAssertEqual(machine.revision, 1)
    }

    func testActionCycleStopsAtConfiguredLimitAndRollsBack() throws {
        var machine = try makeMachine(effectLimit: 4)
        let before = machine.state

        XCTAssertThrowsError(try machine.send(.loop)) {
            XCTAssertEqual(
                $0 as? GameSimulationExecutionError,
                .effectLimitExceeded(limit: 4)
            )
        }

        XCTAssertEqual(machine.state, before)
        XCTAssertEqual(machine.revision, 0)
    }

    func testReducerThrowIsTypedAndRollsBackCheckpoint() throws {
        var machine = try makeMachine()
        let before = machine.state

        XCTAssertThrowsError(try machine.send(.reject)) {
            XCTAssertEqual($0 as? TestRejection, .rejected)
        }

        XCTAssertEqual(machine.state, before)
        XCTAssertEqual(machine.revision, 0)
    }

    func testThrowingTickRollsBackStateTickRevisionAndTrace() throws {
        var state = State()
        state.rejectTick = true
        var machine = try GameSimulationMachine(
            state: state,
            environment: (),
            reducer: Reducer()
        )

        XCTAssertThrowsError(try machine.step()) {
            XCTAssertEqual($0 as? TestRejection, .rejected)
        }

        XCTAssertEqual(machine.state, state)
        XCTAssertEqual(machine.currentTick, 0)
        XCTAssertEqual(machine.revision, 0)
        XCTAssertTrue(machine.trace.isEmpty)
    }

    func testThrowingEntityEventRollsBackRepositoryAndTrace() throws {
        var state = State()
        state.rejectEntityEvent = true
        var machine = try GameSimulationMachine(
            state: state,
            environment: (),
            reducer: Reducer()
        )

        XCTAssertThrowsError(
            try machine.sendSystemAction(.addEntity(.init(id: "rejected")))
        ) {
            XCTAssertEqual($0 as? TestRejection, .rejected)
        }

        XCTAssertEqual(machine.state, state)
        XCTAssertTrue(machine.state.entities.entityIDs.isEmpty)
        XCTAssertEqual(machine.revision, 0)
        XCTAssertTrue(machine.trace.isEmpty)
    }

    func testThrowingNestedEffectRollsBackEarlierFIFOEffectsAndTrace() throws {
        var machine = try makeMachine()
        let before = machine.state

        XCTAssertThrowsError(try machine.send(.nestedReject)) {
            XCTAssertEqual($0 as? TestRejection, .rejected)
        }

        XCTAssertEqual(machine.state, before)
        XCTAssertEqual(machine.revision, 0)
        XCTAssertTrue(machine.trace.isEmpty)
    }

    func testScheduledActionsUseTickThenIDOrderAndCanBeCancelled() throws {
        var machine = try makeMachine()
        try machine.send(.schedule)
        try machine.advance(ticks: 2)

        XCTAssertEqual(machine.state.log, ["due:a", "due:b"])
        XCTAssertFalse(machine.scheduledActionIDs.contains("cancelled"))
        XCTAssertEqual(machine.currentTick, 2)
    }

    func testPauseSpeedAndSingleStepHaveExplicitSemantics() throws {
        var machine = try makeMachine()
        machine.pause()
        try machine.advance(ticks: 2)
        XCTAssertEqual(machine.currentTick, 0)
        try machine.step(ticks: 1)
        XCTAssertEqual(machine.currentTick, 1)
        machine.resume()
        try machine.setSpeed(2)
        try machine.advance(ticks: 2)
        XCTAssertEqual(machine.currentTick, 5)
    }

    func testRemovingParentCleansComponentsLeafFirst() throws {
        var state = State()
        try state.entities.add(.init(id: "parent"))
        try state.entities.add(.init(id: "child", parentID: "parent"))
        state.health["parent"] = Health(entityID: "parent")
        state.health["child"] = Health(entityID: "child")
        var registry = GameComponentRegistry<State>()
        try registry.register(.init(Health.self, at: \State.health))
        var machine = try GameSimulationMachine(
            state: state,
            environment: (),
            reducer: Reducer(),
            configuration: .init(componentRegistry: registry)
        )

        try machine.send(.removeParent)

        XCTAssertEqual(
            machine.state.log,
            ["will:child", "will:parent", "did:child", "did:parent"]
        )
        XCTAssertTrue(machine.state.health.isEmpty)
        XCTAssertTrue(machine.state.entities.entityIDs.isEmpty)
    }

    func testSystemRepositoryFailureIsTypedAndAtomic() throws {
        var machine = try makeMachine()
        XCTAssertThrowsError(
            try machine.sendSystemAction(.removeEntity("missing"))
        ) {
            XCTAssertEqual(
                $0 as? GameSimulationExecutionError,
                .repository(.missingEntity("missing"))
            )
        }
        XCTAssertEqual(machine.revision, 0)
    }

    func testSeededRandomSequenceIsReproducible() throws {
        var left = try makeMachine(seed: 42)
        var right = try makeMachine(seed: 42)
        XCTAssertEqual(left.nextRandom(), right.nextRandom())
        XCTAssertEqual(left.nextRandom(), right.nextRandom())
        XCTAssertEqual(left.randomState, right.randomState)
    }

    func testTickAndRevisionOverflowAreTypedAndAtomic() throws {
        var tickLimited = try GameSimulationMachine(
            state: State(),
            environment: (),
            reducer: Reducer(),
            configuration: .init(currentTick: .max)
        )
        XCTAssertThrowsError(try tickLimited.step()) {
            XCTAssertEqual($0 as? GameSimulationExecutionError, .tickCountOverflow)
        }
        XCTAssertEqual(tickLimited.currentTick, .max)
        XCTAssertEqual(tickLimited.revision, 0)

        var revisionLimited = try GameSimulationMachine(
            state: State(),
            environment: (),
            reducer: Reducer(),
            configuration: .init(revision: .max)
        )
        let before = revisionLimited.state
        XCTAssertThrowsError(try revisionLimited.send(.first)) {
            XCTAssertEqual($0 as? GameSimulationExecutionError, .revisionOverflow)
        }
        XCTAssertEqual(revisionLimited.state, before)
        XCTAssertEqual(revisionLimited.revision, .max)
    }

    func testParityDerivedSeedCannotStartMismatched() {
        let state = ParityState(simulationRevision: 41, simulationTick: 23)
        let machine = GameSimulationMachine(
            parityState: state,
            environment: (),
            reducer: ParityReducer()
        )

        XCTAssertEqual(machine.revision, state.simulationRevision)
        XCTAssertEqual(machine.currentTick, state.simulationTick)
        XCTAssertEqual(machine.state, state)
    }

    private func makeMachine(
        effectLimit: Int = 1_024,
        seed: UInt64 = 0
    ) throws -> GameSimulationMachine<Reducer> {
        try GameSimulationMachine(
            state: State(),
            environment: (),
            reducer: Reducer(),
            configuration: .init(effectLimit: effectLimit, seed: seed)
        )
    }
}

private enum TestRejection: Error, Equatable {
    case rejected
}
