import Foundation
import GameSimulationStateKit

public enum GameSimulationSystemAction: Codable, Equatable, Sendable {
    case addEntity(GameEntityRecord)
    case removeEntity(GameEntityID)
    case setParent(entityID: GameEntityID, parentID: GameEntityID?)
    case addTag(entityID: GameEntityID, tag: String)
    case removeTag(entityID: GameEntityID, tag: String)
}

public indirect enum GameSimulationEffect<Action>: Codable, Equatable, Sendable
where Action: Codable & Equatable & Sendable {
    case none
    case action(Action)
    case system(GameSimulationSystemAction)
    case batch([Self])
    case scheduleAction(id: String, at: GameSimulationTick, action: Action)
    case cancelScheduled(id: String)

    public func mapAction<MappedAction>(
        _ transform: (Action) -> MappedAction
    ) -> GameSimulationEffect<MappedAction>
    where MappedAction: Codable & Equatable & Sendable {
        switch self {
        case .none:
            .none
        case .action(let action):
            .action(transform(action))
        case .system(let action):
            .system(action)
        case .batch(let effects):
            .batch(effects.map { $0.mapAction(transform) })
        case .scheduleAction(let id, let tick, let action):
            .scheduleAction(id: id, at: tick, action: transform(action))
        case .cancelScheduled(let id):
            .cancelScheduled(id: id)
        }
    }
}
