import Foundation

public typealias GameSimulationTick = Int64

/// Entity-free base of the simulation spine.
///
/// Games whose domain state is array/table based (no ECS) conform to this and
/// still get `GameSimulationReducer`, `GameSimulationMachine` and the snapshot
/// path. Only the entity system actions require the ECS layer below.
public protocol GameSimulationBaseState: Codable, Equatable, Sendable {
    static var schemaVersion: Int { get }
}

/// Base state plus the ECS repository.
///
/// This is the historical `GameSimulationState` shape; adopters that already
/// declare `: GameSimulationState` keep compiling unchanged.
public protocol GameSimulationState: GameSimulationBaseState {
    var entities: GameEntityRepository { get set }
}

/// Explicit spelling for the ECS-backed layer.
public typealias GameSimulationEntityState = GameSimulationState
