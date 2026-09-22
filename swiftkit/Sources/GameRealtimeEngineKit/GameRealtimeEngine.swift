import GameRealtimeProtocolKit
import GameRealtimeRuntimeKit
import GameRealtimeStateKit

enum GameRealtimeConfigurationError: Error, Equatable, Sendable {
    case nonPositiveLimit(
        resource: EngineCapacityError.Resource,
        value: Int
    )
    case unsupportedDeterminismProfile
}

enum GameRealtimeEngineError: Error, Equatable, Sendable {
    case missingInput
    case inactiveLifecycle(RuntimeLifecycleState)
    case tickOverflow
    case eventOrdinalOverflow
}

public struct GameRealtimeConfiguration: Sendable {
    public let tickPolicy: TickPolicy
    public let limits: RealtimeLimits
    public let determinism: DeterminismProfile

    public init(
        tickPolicy: TickPolicy = .standardV1,
        limits: RealtimeLimits = .standardV1,
        determinism: DeterminismProfile = .v1
    ) throws {
        for (resource, value) in Self.limitValues(limits) {
            guard value > 0 else {
                throw GameRealtimeConfigurationError.nonPositiveLimit(
                    resource: resource,
                    value: value
                )
            }
        }
        guard determinism == .v1 else {
            throw GameRealtimeConfigurationError
                .unsupportedDeterminismProfile
        }
        _ = try EntityStore(limits: limits)

        self.tickPolicy = tickPolicy
        self.limits = limits
        self.determinism = determinism
    }

    private static func limitValues(
        _ limits: RealtimeLimits
    ) -> [(EngineCapacityError.Resource, Int)] {
        [
            (.entities, limits.totalEntities),
            (.entitiesPerKind, limits.entitiesPerKind),
            (.componentSlotsPerKind, limits.componentSlotsPerKind),
            (
                .registeredComponentKinds,
                limits.registeredComponentKinds
            ),
            (.stableQueryCacheEntries, limits.stableQueryCacheEntries),
            (.deferredCommandsPerTick, limits.deferredCommandsPerTick),
            (.authorityEventsPerTick, limits.authorityEventsPerTick),
            (.queuedInputFrames, limits.queuedInputFrames),
            (
                .broadphaseOccupiedCells,
                limits.broadphaseOccupiedCells
            ),
            (
                .broadphaseCandidatePairsPerTick,
                limits.broadphaseCandidatePairsPerTick
            ),
            (
                .resolvedCollisionPairsPerTick,
                limits.resolvedCollisionPairsPerTick
            ),
            (
                .solverIterationsPerPair,
                limits.solverIterationsPerPair
            ),
            (.checkpointRingLength, limits.checkpointRingLength),
            (.checkpointRingBytes, limits.checkpointRingBytes),
            (.canonicalSnapshotBytes, limits.canonicalSnapshotBytes),
            (.replayInputFrames, limits.replayInputFrames),
            (.outboundSnapshots, limits.outboundSnapshots),
        ]
    }
}

public struct GameRealtimeEngine: Sendable {
    let configuration: GameRealtimeConfiguration

    private var transaction: TickTransaction
    private var mutationInProgress: Bool

    public init(
        configuration: GameRealtimeConfiguration,
        initialState: CanonicalWorldState
    ) throws {
        let entities = try EntityStore(limits: configuration.limits)
        let simulationRNG = DeterministicRNG(seed: initialState.seed)
        let combatRNG = simulationRNG.stream(.combat)
        transaction = try TickTransaction.begin(
            state: TickAuthorityState(
                world: initialState,
                entities: entities
            ),
            rng: [
                .simulation: simulationRNG,
                .combat: combatRNG,
            ],
            queues: AuthorityQueues(limits: configuration.limits),
            codec: CanonicalSnapshotCodec(
                profile: configuration.determinism
            )
        )
        self.configuration = configuration
        mutationInProgress = false
    }

    public mutating func tick(
        input: CombatInputFrame
    ) throws -> TickResult {
        try beginMutation()
        defer {
            mutationInProgress = false
        }

        try transaction.performTick { state, rng, _ in
            let (nextTick, tickOverflow) =
                state.world.tick.addingReportingOverflow(1)
            guard !tickOverflow else {
                throw GameRealtimeEngineError.tickOverflow
            }
            let (nextOrdinal, ordinalOverflow) =
                state.eventOrdinal.addingReportingOverflow(1)
            guard !ordinalOverflow else {
                throw GameRealtimeEngineError.eventOrdinalOverflow
            }
            guard var simulationRNG = rng[.simulation],
                  var combatRNG = rng[.combat]
            else {
                throw SnapshotRestoreError.missingRNGStreamID(
                    RNGStreamID.simulation.rawValue
                )
            }

            let simulationValue = simulationRNG.next()
            let combatValue = combatRNG.next()
            rng[.simulation] = simulationRNG
            rng[.combat] = combatRNG
            state.world.tick = nextTick
            state.eventOrdinal = nextOrdinal
            state.world.seed = simulationValue
                ^ combatValue
                ^ input.sequence
                ^ UInt64(input.buttons.rawValue)
        }
        return TickResult()
    }

    public func snapshot() throws -> CanonicalSnapshot {
        guard !mutationInProgress else {
            throw EngineOwnershipError.reentrantMutation
        }
        return transaction.lastValidSnapshot
    }

    public mutating func restore(
        _ snapshot: CanonicalSnapshot
    ) throws {
        try beginMutation()
        defer {
            mutationInProgress = false
        }
        try transaction.restore(snapshot)
    }

    private mutating func beginMutation() throws {
        guard !mutationInProgress else {
            throw EngineOwnershipError.reentrantMutation
        }
        mutationInProgress = true
    }
}

public actor GameRealtimeEngineSession {
    private var engine: GameRealtimeEngine
    private var accumulator: FixedTickAccumulator
    private var heldInput: CombatInputFrame?
    private var mutationInProgress: Bool
    private var pendingLifecycleTransitions: [RuntimeLifecycleState]

    public init(
        configuration: GameRealtimeConfiguration,
        initialState: CanonicalWorldState
    ) throws {
        engine = try GameRealtimeEngine(
            configuration: configuration,
            initialState: initialState
        )
        accumulator = FixedTickAccumulator(policy: configuration.tickPolicy)
        heldInput = nil
        mutationInProgress = false
        pendingLifecycleTransitions = []
    }

    public func submit(_ input: CombatInputFrame) throws {
        guard !mutationInProgress else {
            throw EngineOwnershipError.reentrantMutation
        }
        heldInput = input
        accumulator.setHeldInput(input)
    }

    public func advanceOneTick() async throws -> TickResult {
        guard accumulator.lifecycle == .active else {
            throw GameRealtimeEngineError.inactiveLifecycle(
                accumulator.lifecycle
            )
        }
        try beginMutation()
        defer {
            finishMutation()
        }
        await Task.yield()
        guard let heldInput else {
            throw GameRealtimeEngineError.missingInput
        }
        return try engine.tick(input: heldInput)
    }

    public func consumeElapsed(
        _ elapsed: Duration
    ) async throws -> GameRealtimeRuntimeKit.AdvanceReport {
        guard accumulator.lifecycle == .active else {
            return accumulator.consume(elapsed: elapsed) { _ in }
        }
        try beginMutation()
        defer {
            finishMutation()
        }
        await Task.yield()
        guard let heldInput else {
            throw GameRealtimeEngineError.missingInput
        }
        return try accumulator.consume(elapsed: elapsed) { _ in
            _ = try engine.tick(input: heldInput)
        }
    }

    public func pause() async {
        requestLifecycleTransition(to: .paused)
    }

    public func resume() async {
        requestLifecycleTransition(to: .active)
    }

    public func snapshot() async throws -> CanonicalSnapshot {
        guard !mutationInProgress else {
            throw EngineOwnershipError.reentrantMutation
        }
        return try engine.snapshot()
    }

    func restore(_ snapshot: CanonicalSnapshot) throws {
        guard !mutationInProgress else {
            throw EngineOwnershipError.reentrantMutation
        }
        try engine.restore(snapshot)
    }

    private func beginMutation() throws {
        guard !mutationInProgress else {
            throw EngineOwnershipError.reentrantMutation
        }
        mutationInProgress = true
    }

    private func finishMutation() {
        mutationInProgress = false
        for transition in pendingLifecycleTransitions {
            applyLifecycleTransition(to: transition)
        }
        pendingLifecycleTransitions.removeAll(keepingCapacity: true)
    }

    private func requestLifecycleTransition(
        to state: RuntimeLifecycleState
    ) {
        if mutationInProgress {
            pendingLifecycleTransitions.append(state)
        } else {
            applyLifecycleTransition(to: state)
        }
    }

    private func applyLifecycleTransition(
        to state: RuntimeLifecycleState
    ) {
        accumulator.transition(to: state)
        if state == .paused || state == .background {
            heldInput = nil
        }
    }
}
