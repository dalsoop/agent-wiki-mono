/// Runtime parity does not require ECS; it only mirrors revision/tick.
public protocol GameSimulationRuntimeParityState: GameSimulationBaseState {
    var simulationRevision: Int64 { get set }
    var simulationTick: GameSimulationTick { get set }
}
