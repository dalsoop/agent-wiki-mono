import XCTest
import GameSimulationStateKit
@testable import GameSimulationReducerKit

final class GameSimulationReducerTests: XCTestCase {
    private enum Action: String, Codable, Equatable, Sendable {
        case first
        case second
        case ignored
    }

    private struct State: GameSimulationState {
        static let schemaVersion = 1
        var entities = GameEntityRepository()
        var log: [String] = []
        var lastThrottleTick: GameSimulationTick = 0
    }

    private struct RecordingReducer: GameSimulationReducer {
        func reduceTick(
            state: inout State,
            tick: GameSimulationTick,
            environment: String
        ) -> GameSimulationEffect<Action> {
            state.log.append("\(environment)tick:\(tick)")
            return .none
        }

        func reduceAction(
            state: inout State,
            action: Action,
            environment: String
        ) -> GameSimulationEffect<Action> {
            state.log.append("\(environment)action:\(action.rawValue)")
            return .none
        }

        func reduceEntityEvent(
            state: inout State,
            event: GameSimulationEntityEvent,
            environment: String
        ) -> GameSimulationEffect<Action> {
            state.log.append("\(environment)event:\(event.label)")
            return .none
        }
    }

    func testResendStillForwardsTickAndEntityEvents() throws {
        var state = State()
        let reducer = RecordingReducer().resending { action in
            action == .first ? .second : nil
        }
        _ = try reducer.reduceTick(state: &state, tick: 1, environment: "")
        _ = try reducer.reduceEntityEvent(
            state: &state,
            event: .added("hero"),
            environment: ""
        )
        let effect = try reducer.reduceAction(
            state: &state,
            action: .first,
            environment: ""
        )

        XCTAssertEqual(state.log, ["tick:1", "event:added:hero", "action:first"])
        XCTAssertEqual(effect, .batch([.none, .action(.second)]))
    }

    func testReducerSequenceRunsInDeclarationOrder() throws {
        var state = State()
        let first = AnyGameSimulationReducer<State, Action, String>(
            reduceAction: { state, _, _ in state.log.append("first"); return .none }
        )
        let second = AnyGameSimulationReducer<State, Action, String>(
            reduceAction: { state, _, _ in state.log.append("second"); return .none }
        )
        let reducer = GameSimulationReducerSequence([first, second])

        let effect = try reducer.reduceAction(
            state: &state,
            action: .first,
            environment: ""
        )

        XCTAssertEqual(state.log, ["first", "second"])
        XCTAssertEqual(effect, .batch([.none, .none]))
    }

    func testFilterAppliesToAllInputPathsWithoutMutatingWhenFalse() throws {
        var state = State()
        let reducer = RecordingReducer().filtered { _, action in action != .ignored }

        XCTAssertEqual(
            try reducer.reduceAction(state: &state, action: .ignored, environment: ""),
            .none
        )
        XCTAssertTrue(state.log.isEmpty)
        _ = try reducer.reduceTick(state: &state, tick: 1, environment: "")
        XCTAssertEqual(state.log, ["tick:1"])
    }

    func testPullbackMapsStateActionEnvironmentAndEffects() throws {
        struct GlobalState: GameSimulationState {
            static let schemaVersion = 1
            var entities = GameEntityRepository()
            var local = State()
        }
        enum GlobalAction: Codable, Equatable, Sendable {
            case local(Action)
            case other
        }

        var state = GlobalState()
        let reducer = RecordingReducer().pullback(
            state: \GlobalState.local,
            extractAction: { action in
                guard case .local(let local) = action else { return nil }
                return local
            },
            embedAction: GlobalAction.local,
            environment: { (_: Int) in "global:" }
        )

        let effect = try reducer.reduceAction(
            state: &state,
            action: .local(.first),
            environment: 1
        )

        XCTAssertEqual(state.local.log, ["global:action:first"])
        XCTAssertEqual(effect, .none)
    }

    func testThrottleUsesCodableStateAndForwardsActionsAndEvents() throws {
        var state = State()
        let reducer = RecordingReducer().throttled(
            lastRunTick: \State.lastThrottleTick,
            minimumTicks: 3
        )

        _ = try reducer.reduceTick(state: &state, tick: 2, environment: "")
        _ = try reducer.reduceTick(state: &state, tick: 3, environment: "")
        _ = try reducer.reduceTick(state: &state, tick: 5, environment: "")
        _ = try reducer.reduceTick(state: &state, tick: 6, environment: "")
        _ = try reducer.reduceAction(state: &state, action: .first, environment: "")
        _ = try reducer.reduceEntityEvent(
            state: &state,
            event: .willRemove("hero"),
            environment: ""
        )

        XCTAssertEqual(state.lastThrottleTick, 6)
        XCTAssertEqual(
            state.log,
            ["tick:3", "tick:6", "action:first", "event:will-remove:hero"]
        )
    }

    func testEffectMapActionMapsNestedAndScheduledActions() {
        enum GlobalAction: Codable, Equatable, Sendable { case local(Action) }
        let effect = GameSimulationEffect<Action>.batch([
            .action(.first),
            .scheduleAction(id: "later", at: 3, action: .second),
            .system(.addTag(entityID: "hero", tag: "leader")),
        ])

        XCTAssertEqual(
            effect.mapAction(GlobalAction.local),
            .batch([
                .action(.local(.first)),
                .scheduleAction(id: "later", at: 3, action: .local(.second)),
                .system(.addTag(entityID: "hero", tag: "leader")),
            ])
        )
    }
}

private extension GameSimulationEntityEvent {
    var label: String {
        switch self {
        case .added(let id): "added:\(id.rawValue)"
        case .willRemove(let id): "will-remove:\(id.rawValue)"
        case .didRemove(let id): "did-remove:\(id.rawValue)"
        }
    }
}
