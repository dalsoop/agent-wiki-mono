import Foundation
import GameSimulationStateKit

public struct AnyGameSimulationReducer<
    State: GameSimulationBaseState,
    Action: Codable & Equatable & Sendable,
    Environment
>: GameSimulationReducer {
    private let tickBody: (
        inout State,
        GameSimulationTick,
        Environment
    ) throws -> GameSimulationEffect<Action>
    private let actionBody: (
        inout State,
        Action,
        Environment
    ) throws -> GameSimulationEffect<Action>
    private let entityEventBody: (
        inout State,
        GameSimulationEntityEvent,
        Environment
    ) throws -> GameSimulationEffect<Action>

    public init(
        reduceTick: @escaping (
            inout State,
            GameSimulationTick,
            Environment
        ) throws -> GameSimulationEffect<Action> = { _, _, _ in .none },
        reduceAction: @escaping (
            inout State,
            Action,
            Environment
        ) throws -> GameSimulationEffect<Action> = { _, _, _ in .none },
        reduceEntityEvent: @escaping (
            inout State,
            GameSimulationEntityEvent,
            Environment
        ) throws -> GameSimulationEffect<Action> = { _, _, _ in .none }
    ) {
        tickBody = reduceTick
        actionBody = reduceAction
        entityEventBody = reduceEntityEvent
    }

    public init<R: GameSimulationReducer>(_ reducer: R)
    where R.State == State, R.Action == Action, R.Environment == Environment {
        tickBody = reducer.reduceTick
        actionBody = reducer.reduceAction
        entityEventBody = reducer.reduceEntityEvent
    }

    public func reduceTick(
        state: inout State,
        tick: GameSimulationTick,
        environment: Environment
    ) throws -> GameSimulationEffect<Action> {
        try tickBody(&state, tick, environment)
    }

    public func reduceAction(
        state: inout State,
        action: Action,
        environment: Environment
    ) throws -> GameSimulationEffect<Action> {
        try actionBody(&state, action, environment)
    }

    public func reduceEntityEvent(
        state: inout State,
        event: GameSimulationEntityEvent,
        environment: Environment
    ) throws -> GameSimulationEffect<Action> {
        try entityEventBody(&state, event, environment)
    }
}

public extension GameSimulationReducer {
    func eraseToAnyReducer() -> AnyGameSimulationReducer<State, Action, Environment> {
        AnyGameSimulationReducer(self)
    }
}

public struct GameSimulationReducerSequence<
    State: GameSimulationBaseState,
    Action: Codable & Equatable & Sendable,
    Environment
>: GameSimulationReducer {
    public var reducers: [AnyGameSimulationReducer<State, Action, Environment>]

    public init(_ reducers: [AnyGameSimulationReducer<State, Action, Environment>]) {
        self.reducers = reducers
    }

    public func reduceTick(
        state: inout State,
        tick: GameSimulationTick,
        environment: Environment
    ) throws -> GameSimulationEffect<Action> {
        .batch(try reducers.map {
            try $0.reduceTick(state: &state, tick: tick, environment: environment)
        })
    }

    public func reduceAction(
        state: inout State,
        action: Action,
        environment: Environment
    ) throws -> GameSimulationEffect<Action> {
        .batch(try reducers.map {
            try $0.reduceAction(state: &state, action: action, environment: environment)
        })
    }

    public func reduceEntityEvent(
        state: inout State,
        event: GameSimulationEntityEvent,
        environment: Environment
    ) throws -> GameSimulationEffect<Action> {
        .batch(try reducers.map {
            try $0.reduceEntityEvent(state: &state, event: event, environment: environment)
        })
    }
}
