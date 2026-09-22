import Foundation
import GameSimulationStateKit

public extension GameSimulationReducer {
    func resending(
        _ transform: @escaping (Action) -> Action?
    ) -> AnyGameSimulationReducer<State, Action, Environment> {
        AnyGameSimulationReducer(
            reduceTick: reduceTick,
            reduceAction: { state, action, environment in
                let base = try reduceAction(
                    state: &state,
                    action: action,
                    environment: environment
                )
                guard let mapped = transform(action) else { return base }
                return .batch([base, .action(mapped)])
            },
            reduceEntityEvent: reduceEntityEvent
        )
    }

    func filtered(
        _ predicate: @escaping (State, Action?) -> Bool
    ) -> AnyGameSimulationReducer<State, Action, Environment> {
        AnyGameSimulationReducer(
            reduceTick: { state, tick, environment in
                guard predicate(state, nil) else { return .none }
                return try reduceTick(state: &state, tick: tick, environment: environment)
            },
            reduceAction: { state, action, environment in
                guard predicate(state, action) else { return .none }
                return try reduceAction(state: &state, action: action, environment: environment)
            },
            reduceEntityEvent: { state, event, environment in
                guard predicate(state, nil) else { return .none }
                return try reduceEntityEvent(
                    state: &state,
                    event: event,
                    environment: environment
                )
            }
        )
    }

    func pullback<GlobalState, GlobalAction, GlobalEnvironment>(
        state stateKeyPath: WritableKeyPath<GlobalState, State>,
        extractAction: @escaping (GlobalAction) -> Action?,
        embedAction: @escaping (Action) -> GlobalAction,
        environment environmentTransform: @escaping (GlobalEnvironment) -> Environment
    ) -> AnyGameSimulationReducer<GlobalState, GlobalAction, GlobalEnvironment>
    where GlobalState: GameSimulationBaseState,
          GlobalAction: Codable & Equatable & Sendable {
        AnyGameSimulationReducer<GlobalState, GlobalAction, GlobalEnvironment>(
            reduceTick: { globalState, tick, globalEnvironment in
                try reduceTick(
                    state: &globalState[keyPath: stateKeyPath],
                    tick: tick,
                    environment: environmentTransform(globalEnvironment)
                )
                .mapAction(embedAction)
            },
            reduceAction: { globalState, globalAction, globalEnvironment in
                guard let localAction = extractAction(globalAction) else { return .none }
                return try reduceAction(
                    state: &globalState[keyPath: stateKeyPath],
                    action: localAction,
                    environment: environmentTransform(globalEnvironment)
                )
                .mapAction(embedAction)
            },
            reduceEntityEvent: { globalState, event, globalEnvironment in
                try reduceEntityEvent(
                    state: &globalState[keyPath: stateKeyPath],
                    event: event,
                    environment: environmentTransform(globalEnvironment)
                )
                .mapAction(embedAction)
            }
        )
    }

    func throttled(
        lastRunTick: WritableKeyPath<State, GameSimulationTick>,
        minimumTicks: GameSimulationTick
    ) -> AnyGameSimulationReducer<State, Action, Environment> {
        let interval = max(1, minimumTicks)
        return AnyGameSimulationReducer(
            reduceTick: { state, tick, environment in
                let elapsed = tick - state[keyPath: lastRunTick]
                guard elapsed >= interval else { return .none }
                state[keyPath: lastRunTick] = tick
                return try reduceTick(state: &state, tick: tick, environment: environment)
            },
            reduceAction: reduceAction,
            reduceEntityEvent: reduceEntityEvent
        )
    }
}
