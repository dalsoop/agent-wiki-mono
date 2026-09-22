import Foundation
import GameSimulationStateKit

public enum GameSimulationEntityEvent: Codable, Equatable, Sendable {
    case added(GameEntityID)
    case willRemove(GameEntityID)
    case didRemove(GameEntityID)
}

public protocol GameSimulationReducer {
    associatedtype State: GameSimulationBaseState
    associatedtype Action: Codable & Equatable & Sendable
    associatedtype Environment

    func reduceTick(
        state: inout State,
        tick: GameSimulationTick,
        environment: Environment
    ) throws -> GameSimulationEffect<Action>

    func reduceAction(
        state: inout State,
        action: Action,
        environment: Environment
    ) throws -> GameSimulationEffect<Action>

    func reduceEntityEvent(
        state: inout State,
        event: GameSimulationEntityEvent,
        environment: Environment
    ) throws -> GameSimulationEffect<Action>
}

public extension GameSimulationReducer {
    func reduceTick(
        state: inout State,
        tick: GameSimulationTick,
        environment: Environment
    ) throws -> GameSimulationEffect<Action> {
        .none
    }

    func reduceAction(
        state: inout State,
        action: Action,
        environment: Environment
    ) throws -> GameSimulationEffect<Action> {
        .none
    }

    func reduceEntityEvent(
        state: inout State,
        event: GameSimulationEntityEvent,
        environment: Environment
    ) throws -> GameSimulationEffect<Action> {
        .none
    }
}
