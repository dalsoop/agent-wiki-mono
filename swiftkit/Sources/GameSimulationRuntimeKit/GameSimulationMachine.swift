import Foundation
import GameSimulationStateKit
import GameSimulationReducerKit

public enum GameSimulationExecutionError: Error, Equatable, Sendable {
    case invalidTickCount(GameSimulationTick)
    case tickCountOverflow
    case invalidSpeed(Int)
    case revisionOverflow
    case stateRevisionMismatch(state: Int64, machine: Int64)
    case stateTickMismatch(state: GameSimulationTick, machine: GameSimulationTick)
    case stateParitySynchronizationFailed
    case effectLimitExceeded(limit: Int)
    case repository(GameEntityRepositoryError)
    /// The state does not conform to `GameSimulationEntityState`, so entity
    /// system actions have no repository to act on.
    case entitiesUnsupported

    public var code: String {
        switch self {
        case .invalidTickCount: "runtime.invalid-tick-count"
        case .tickCountOverflow: "runtime.tick-count-overflow"
        case .invalidSpeed: "runtime.invalid-speed"
        case .revisionOverflow: "runtime.revision-overflow"
        case .stateRevisionMismatch: "runtime.state-revision-mismatch"
        case .stateTickMismatch: "runtime.state-tick-mismatch"
        case .stateParitySynchronizationFailed: "runtime.state-parity-synchronization-failed"
        case .effectLimitExceeded: "runtime.effect-limit-exceeded"
        case .repository(let error): error.code
        case .entitiesUnsupported: "runtime.entities-unsupported"
        }
    }
}

public struct GameSimulationRandomState: Codable, Equatable, Sendable {
    public private(set) var value: UInt64

    public init(seed: UInt64) {
        value = seed
    }

    public mutating func next() -> UInt64 {
        value &+= 0x9E37_79B9_7F4A_7C15
        var result = value
        result = (result ^ (result >> 30)) &* 0xBF58_476D_1CE4_E5B9
        result = (result ^ (result >> 27)) &* 0x94D0_49BB_1331_11EB
        return result ^ (result >> 31)
    }
}

public struct GameSimulationScheduledAction<Action>: Codable, Equatable, Sendable
where Action: Codable & Equatable & Sendable {
    public var id: String
    public var tick: GameSimulationTick
    public var action: Action

    public init(id: String, tick: GameSimulationTick, action: Action) {
        self.id = id
        self.tick = tick
        self.action = action
    }
}

public struct GameSimulationTraceEntry: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case action
        case effect
        case system
        case tick
    }

    public var sequence: Int64
    public var revision: Int64
    public var tick: GameSimulationTick
    public var kind: Kind

    public init(
        sequence: Int64,
        revision: Int64,
        tick: GameSimulationTick,
        kind: Kind
    ) {
        self.sequence = sequence
        self.revision = revision
        self.tick = tick
        self.kind = kind
    }
}

public struct GameSimulationMachine<R: GameSimulationReducer> {
    public private(set) var state: R.State
    public private(set) var revision: Int64
    public private(set) var currentTick: GameSimulationTick
    public private(set) var isPaused: Bool
    public private(set) var speed: Int
    public private(set) var randomState: GameSimulationRandomState
    public private(set) var trace: [GameSimulationTraceEntry]

    private let environment: R.Environment
    private let reducer: R
    private let componentRegistry: GameComponentRegistry<R.State>
    private let effectLimit: Int
    private var scheduledActions: [String: GameSimulationScheduledAction<R.Action>]
    private var traceSequence: Int64

    public struct Configuration: Sendable {
        public var componentRegistry: GameComponentRegistry<R.State>
        public var effectLimit: Int
        public var seed: UInt64
        public var revision: Int64
        public var currentTick: GameSimulationTick
        public var isPaused: Bool
        public var speed: Int
        public var scheduledActions: [GameSimulationScheduledAction<R.Action>]

        public init(
            componentRegistry: GameComponentRegistry<R.State> = .init(),
            effectLimit: Int = 1_024,
            seed: UInt64 = 0,
            revision: Int64 = 0,
            currentTick: GameSimulationTick = 0,
            isPaused: Bool = false,
            speed: Int = 1,
            scheduledActions: [GameSimulationScheduledAction<R.Action>] = []
        ) {
            self.componentRegistry = componentRegistry
            self.effectLimit = effectLimit
            self.seed = seed
            self.revision = revision
            self.currentTick = currentTick
            self.isPaused = isPaused
            self.speed = speed
            self.scheduledActions = scheduledActions
        }
    }

    public init(
        state: R.State,
        environment: R.Environment,
        reducer: R,
        configuration: Configuration = Configuration()
    ) throws {
        self.state = state
        self.environment = environment
        self.reducer = reducer
        self.componentRegistry = configuration.componentRegistry
        self.effectLimit = max(1, configuration.effectLimit)
        self.randomState = GameSimulationRandomState(seed: configuration.seed)
        self.revision = configuration.revision
        self.currentTick = configuration.currentTick
        self.isPaused = configuration.isPaused
        self.speed = min(max(configuration.speed, 1), 16)
        self.scheduledActions = Dictionary(
            configuration.scheduledActions.map { ($0.id, $0) },
            uniquingKeysWith: { _, newest in newest }
        )
        trace = []
        traceSequence = 0
        try validateStateParity()
    }

    /// Seeds both runtime counters from the embedded parity state, so a
    /// mismatched machine cannot be constructed through this initializer.
    public init(
        parityState state: R.State,
        environment: R.Environment,
        reducer: R,
        configuration: Configuration = Configuration()
    ) where R.State: GameSimulationRuntimeParityState {
        self.state = state
        self.environment = environment
        self.reducer = reducer
        self.componentRegistry = configuration.componentRegistry
        self.effectLimit = max(1, configuration.effectLimit)
        randomState = GameSimulationRandomState(seed: configuration.seed)
        revision = state.simulationRevision
        currentTick = state.simulationTick
        self.isPaused = configuration.isPaused
        self.speed = min(max(configuration.speed, 1), 16)
        self.scheduledActions = Dictionary(
            configuration.scheduledActions.map { ($0.id, $0) },
            uniquingKeysWith: { _, newest in newest }
        )
        trace = []
        traceSequence = 0
    }

    public var scheduledActionIDs: [String] {
        scheduledActions.keys.sorted()
    }

    public var scheduledActionValues: [GameSimulationScheduledAction<R.Action>] {
        scheduledActions.values.sorted {
            ($0.tick, $0.id) < ($1.tick, $1.id)
        }
    }

    @discardableResult
    public mutating func nextRandom() -> UInt64 {
        randomState.next()
    }

    public mutating func pause() {
        isPaused = true
    }

    public mutating func resume() {
        isPaused = false
    }

    public mutating func setSpeed(_ speed: Int) throws {
        guard (1 ... 16).contains(speed) else {
            throw GameSimulationExecutionError.invalidSpeed(speed)
        }
        self.speed = speed
    }

    public mutating func send(_ action: R.Action) throws {
        try validateStateParity()
        try validateRevisionAdvance()
        let checkpoint = makeCheckpoint()
        do {
            appendTrace(.action)
            let effect = try reducer.reduceAction(
                state: &state,
                action: action,
                environment: environment
            )
            try drain(effect)
            revision += 1
            try validateStateParity()
        } catch {
            restore(checkpoint)
            throw error
        }
    }

    public mutating func sendSystemAction(
        _ action: GameSimulationSystemAction
    ) throws {
        try validateStateParity()
        try validateRevisionAdvance()
        let checkpoint = makeCheckpoint()
        do {
            try drain(.system(action))
            revision += 1
            try validateStateParity()
        } catch {
            restore(checkpoint)
            throw error
        }
    }

    public mutating func advance(ticks: GameSimulationTick) throws {
        guard ticks >= 0 else {
            throw GameSimulationExecutionError.invalidTickCount(ticks)
        }
        guard !isPaused else { return }
        let (scaledTicks, overflow) = ticks.multipliedReportingOverflow(by: Int64(speed))
        guard !overflow else {
            throw GameSimulationExecutionError.tickCountOverflow
        }
        try advanceExact(ticks: scaledTicks)
    }

    public mutating func step(ticks: GameSimulationTick = 1) throws {
        guard ticks >= 0 else {
            throw GameSimulationExecutionError.invalidTickCount(ticks)
        }
        try advanceExact(ticks: ticks)
    }

    private mutating func advanceExact(ticks: GameSimulationTick) throws {
        try validateStateParity()
        let (_, tickOverflow) = currentTick.addingReportingOverflow(ticks)
        guard !tickOverflow else {
            throw GameSimulationExecutionError.tickCountOverflow
        }
        let (_, revisionOverflow) = revision.addingReportingOverflow(ticks)
        guard !revisionOverflow else {
            throw GameSimulationExecutionError.revisionOverflow
        }
        let checkpoint = makeCheckpoint()
        do {
            for _ in 0 ..< ticks {
                currentTick += 1
                appendTrace(.tick)
                let due = scheduledActions.values
                    .filter { $0.tick <= currentTick }
                    .sorted { ($0.tick, $0.id) < ($1.tick, $1.id) }
                for scheduled in due {
                    scheduledActions[scheduled.id] = nil
                }
                if !due.isEmpty {
                    try drain(.batch(due.map { .action($0.action) }))
                }
                let tickEffect = try reducer.reduceTick(
                    state: &state,
                    tick: currentTick,
                    environment: environment
                )
                try drain(tickEffect)
                revision += 1
                try validateStateParity()
            }
        } catch {
            restore(checkpoint)
            throw error
        }
    }

    private mutating func drain(_ initialEffect: GameSimulationEffect<R.Action>) throws {
        var queue = [initialEffect]
        var cursor = 0
        var processed = 0

        while cursor < queue.count {
            guard processed < effectLimit else {
                throw GameSimulationExecutionError.effectLimitExceeded(limit: effectLimit)
            }
            let effect = queue[cursor]
            cursor += 1
            processed += 1
            appendTrace(.effect)

            switch effect {
            case .none:
                break
            case .action(let action):
                appendTrace(.action)
                queue.append(try reducer.reduceAction(
                    state: &state,
                    action: action,
                    environment: environment
                ))
            case .system(let action):
                appendTrace(.system)
                queue.append(try applySystemAction(action))
            case .batch(let effects):
                queue.append(contentsOf: effects)
            case .scheduleAction(let id, let tick, let action):
                scheduledActions[id] = .init(id: id, tick: tick, action: action)
            case .cancelScheduled(let id):
                scheduledActions[id] = nil
            }
        }
    }

    private mutating func applySystemAction(
        _ action: GameSimulationSystemAction
    ) throws -> GameSimulationEffect<R.Action> {
        do {
            switch action {
            case .addEntity(let record):
                try withEntities { try $0.add(record) }
                return try reducer.reduceEntityEvent(
                    state: &state,
                    event: .added(record.id),
                    environment: environment
                )
            case .removeEntity(let entityID):
                let order = try withEntities { try $0.removalOrder(rootedAt: entityID) }
                var effects: [GameSimulationEffect<R.Action>] = []
                for id in order {
                    effects.append(try reducer.reduceEntityEvent(
                        state: &state,
                        event: .willRemove(id),
                        environment: environment
                    ))
                    componentRegistry.removeAll(for: id, from: &state)
                }
                _ = try withEntities { try $0.removeSubtree(rootedAt: entityID) }
                for id in order {
                    effects.append(try reducer.reduceEntityEvent(
                        state: &state,
                        event: .didRemove(id),
                        environment: environment
                    ))
                }
                return .batch(effects)
            case .setParent(let entityID, let parentID):
                try withEntities { try $0.setParent(of: entityID, to: parentID) }
                return .none
            case .addTag(let entityID, let tag):
                try withEntities { try $0.addTag(tag, to: entityID) }
                return .none
            case .removeTag(let entityID, let tag):
                try withEntities { try $0.removeTag(tag, from: entityID) }
                return .none
            }
        } catch let error as GameEntityRepositoryError {
            throw GameSimulationExecutionError.repository(error)
        }
    }

    /// Bridges the entity system actions onto the optional ECS layer.
    ///
    /// States that only conform to `GameSimulationBaseState` have no
    /// repository; entity system actions then fail instead of forcing every
    /// game to carry a dead `GameEntityRepository`.
    @discardableResult
    private mutating func withEntities<Value>(
        _ body: (inout GameEntityRepository) throws -> Value
    ) throws -> Value {
        guard var entityState = state as? any GameSimulationEntityState else {
            throw GameSimulationExecutionError.entitiesUnsupported
        }
        let value = try body(&entityState.entities)
        guard let updated = entityState as? R.State else {
            throw GameSimulationExecutionError.stateParitySynchronizationFailed
        }
        state = updated
        return value
    }

    private mutating func appendTrace(_ kind: GameSimulationTraceEntry.Kind) {
        if traceSequence < .max {
            traceSequence += 1
        }
        trace.append(.init(
            sequence: traceSequence,
            revision: revision,
            tick: currentTick,
            kind: kind
        ))
        if trace.count > 512 {
            trace.removeFirst(trace.count - 512)
        }
    }

    private typealias Checkpoint = (
        state: R.State,
        revision: Int64,
        tick: GameSimulationTick,
        paused: Bool,
        speed: Int,
        random: GameSimulationRandomState,
        scheduled: [String: GameSimulationScheduledAction<R.Action>],
        trace: [GameSimulationTraceEntry],
        traceSequence: Int64
    )

    private func makeCheckpoint() -> Checkpoint {
        (
            state, revision, currentTick, isPaused, speed, randomState,
            scheduledActions, trace, traceSequence
        )
    }

    private mutating func restore(_ checkpoint: Checkpoint) {
        state = checkpoint.state
        revision = checkpoint.revision
        currentTick = checkpoint.tick
        isPaused = checkpoint.paused
        speed = checkpoint.speed
        randomState = checkpoint.random
        scheduledActions = checkpoint.scheduled
        trace = checkpoint.trace
        traceSequence = checkpoint.traceSequence
    }

    mutating func restoreSnapshotValues(
        state: R.State,
        revision: Int64,
        currentTick: GameSimulationTick,
        isPaused: Bool,
        speed: Int,
        randomState: GameSimulationRandomState,
        scheduledActions: [GameSimulationScheduledAction<R.Action>]
    ) {
        self.state = state
        self.revision = revision
        self.currentTick = currentTick
        self.isPaused = isPaused
        self.speed = speed
        self.randomState = randomState
        self.scheduledActions = Dictionary(
            scheduledActions.map { ($0.id, $0) },
            uniquingKeysWith: { _, newest in newest }
        )
        trace = []
        traceSequence = 0
    }

    func validateControlMutation() throws {
        try validateRevisionAdvance()
    }

    mutating func commitValidatedControlMutation() throws {
        let nextRevision = revision + 1
        guard var parityState = state as? any GameSimulationRuntimeParityState else {
            revision = nextRevision
            return
        }
        parityState.simulationRevision = nextRevision
        guard let synchronizedState = parityState as? R.State else {
            throw GameSimulationExecutionError.stateParitySynchronizationFailed
        }
        state = synchronizedState
        revision = nextRevision
    }

    private func validateRevisionAdvance() throws {
        guard revision < .max else {
            throw GameSimulationExecutionError.revisionOverflow
        }
    }

    func validateStateParity() throws {
        try GameSimulationRuntimeParityValidator.validate(
            state: state,
            revision: revision,
            tick: currentTick
        )
    }
}

enum GameSimulationRuntimeParityValidator {
    static func validate<State>(
        state: State,
        revision: Int64,
        tick: GameSimulationTick
    ) throws {
        guard let parityState = state as? any GameSimulationRuntimeParityState else {
            return
        }
        guard parityState.simulationRevision == revision else {
            throw GameSimulationExecutionError.stateRevisionMismatch(
                state: parityState.simulationRevision,
                machine: revision
            )
        }
        guard parityState.simulationTick == tick else {
            throw GameSimulationExecutionError.stateTickMismatch(
                state: parityState.simulationTick,
                machine: tick
            )
        }
    }
}

extension GameSimulationMachine: Sendable
where R: Sendable, R.Environment: Sendable {}
