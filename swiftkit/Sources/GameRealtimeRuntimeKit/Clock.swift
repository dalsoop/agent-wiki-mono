import GameRealtimeProtocolKit

public enum BacklogPolicy: UInt8, Codable, Hashable, Sendable {
    case discardAfterCatchUpLimit = 1
}

public enum TickPolicyError: Error, Equatable, Sendable {
    case nonPositiveFixedStep(Duration)
    case nonPositiveMaxCatchUpTicks(Int)
    case nonPositiveMaxElapsedClamp(Duration)
}

public struct TickPolicy: Codable, Hashable, Sendable {
    public let fixedStep: Duration
    public let maxCatchUpTicks: Int
    public let maxElapsedClamp: Duration
    public let backlogPolicy: BacklogPolicy

    public init(
        fixedStep: Duration,
        maxCatchUpTicks: Int,
        maxElapsedClamp: Duration,
        backlogPolicy: BacklogPolicy
    ) throws {
        guard fixedStep > .zero else {
            throw TickPolicyError.nonPositiveFixedStep(fixedStep)
        }
        guard maxCatchUpTicks > 0 else {
            throw TickPolicyError.nonPositiveMaxCatchUpTicks(
                maxCatchUpTicks
            )
        }
        guard maxElapsedClamp > .zero else {
            throw TickPolicyError.nonPositiveMaxElapsedClamp(
                maxElapsedClamp
            )
        }
        self.fixedStep = fixedStep
        self.maxCatchUpTicks = maxCatchUpTicks
        self.maxElapsedClamp = maxElapsedClamp
        self.backlogPolicy = backlogPolicy
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            fixedStep: container.decode(
                Duration.self,
                forKey: .fixedStep
            ),
            maxCatchUpTicks: container.decode(
                Int.self,
                forKey: .maxCatchUpTicks
            ),
            maxElapsedClamp: container.decode(
                Duration.self,
                forKey: .maxElapsedClamp
            ),
            backlogPolicy: container.decode(
                BacklogPolicy.self,
                forKey: .backlogPolicy
            )
        )
    }

    private init(
        validatedFixedStep fixedStep: Duration,
        maxCatchUpTicks: Int,
        maxElapsedClamp: Duration,
        backlogPolicy: BacklogPolicy
    ) {
        self.fixedStep = fixedStep
        self.maxCatchUpTicks = maxCatchUpTicks
        self.maxElapsedClamp = maxElapsedClamp
        self.backlogPolicy = backlogPolicy
    }

    public static let standardV1 = TickPolicy(
        validatedFixedStep: .seconds(1) / 30,
        maxCatchUpTicks: 5,
        maxElapsedClamp: .milliseconds(250),
        backlogPolicy: .discardAfterCatchUpLimit
    )
}

public protocol GameRealtimeClock: Sendable {
    func now() -> ContinuousClock.Instant
}

public enum ManualGameRealtimeClockError: Error, Equatable, Sendable {
    case negativeAdvance(Duration)
}

public struct ManualGameRealtimeClock: GameRealtimeClock, Sendable {
    private var instant: ContinuousClock.Instant

    public init(startingAt instant: ContinuousClock.Instant) {
        self.instant = instant
    }

    public func now() -> ContinuousClock.Instant {
        instant
    }

    public mutating func advance(by duration: Duration) throws {
        guard duration >= .zero else {
            throw ManualGameRealtimeClockError.negativeAdvance(duration)
        }
        instant = instant.advanced(by: duration)
    }
}

public enum RuntimeLifecycleState: UInt8, Codable, Hashable, Sendable {
    case active = 1
    case paused = 2
    case background = 3
    case faulted = 4
}

public struct AdvanceReport: Hashable, Sendable {
    public let suppliedElapsed: Duration
    public let consumedElapsed: Duration
    public let executedTicks: Int
    public let discardedTicks: Int
    public let remainingElapsed: Duration

    public init(
        suppliedElapsed: Duration,
        consumedElapsed: Duration,
        executedTicks: Int,
        discardedTicks: Int,
        remainingElapsed: Duration
    ) {
        self.suppliedElapsed = suppliedElapsed
        self.consumedElapsed = consumedElapsed
        self.executedTicks = executedTicks
        self.discardedTicks = discardedTicks
        self.remainingElapsed = remainingElapsed
    }
}

public struct FixedTickAccumulator: Sendable {
    public let policy: TickPolicy
    public private(set) var lifecycle: RuntimeLifecycleState
    public private(set) var accumulatedElapsed: Duration
    public private(set) var heldInput: CombatInputFrame?
    public private(set) var pendingRawInputs: [CombatInputFrame]

    public init(
        policy: TickPolicy = .standardV1,
        lifecycle: RuntimeLifecycleState = .active
    ) {
        self.policy = policy
        self.lifecycle = lifecycle
        accumulatedElapsed = .zero
        heldInput = nil
        pendingRawInputs = []
    }

    public mutating func setHeldInput(_ input: CombatInputFrame?) {
        heldInput = input
    }

    public mutating func enqueuePendingRawInput(
        _ input: CombatInputFrame
    ) throws {
        let attempted = pendingRawInputs.count + 1
        let limit = RealtimeLimits.standardV1.queuedInputFrames
        guard attempted <= limit else {
            throw EngineCapacityError(
                resource: .queuedInputFrames,
                limit: limit,
                attempted: attempted
            )
        }
        pendingRawInputs.append(input)
    }

    public mutating func transition(to state: RuntimeLifecycleState) {
        lifecycle = state
        if state == .paused || state == .background {
            clearTimingAndInput()
        }
    }

    public mutating func consume(
        elapsed: Duration,
        tick: (Duration) throws -> Void
    ) rethrows -> AdvanceReport {
        guard lifecycle == .active else {
            return AdvanceReport(
                suppliedElapsed: elapsed,
                consumedElapsed: .zero,
                executedTicks: 0,
                discardedTicks: 0,
                remainingElapsed: .zero
            )
        }

        let nonnegativeElapsed = max(elapsed, .zero)
        let clampedElapsed = min(nonnegativeElapsed, policy.maxElapsedClamp)
        accumulatedElapsed += clampedElapsed

        var executedTicks = 0
        while accumulatedElapsed >= policy.fixedStep,
              executedTicks < policy.maxCatchUpTicks
        {
            try tick(policy.fixedStep)
            accumulatedElapsed -= policy.fixedStep
            executedTicks += 1
        }

        var discardedTicks = 0
        if accumulatedElapsed >= policy.fixedStep,
           policy.backlogPolicy == .discardAfterCatchUpLimit
        {
            while accumulatedElapsed >= policy.fixedStep {
                accumulatedElapsed -= policy.fixedStep
                discardedTicks += 1
            }
            accumulatedElapsed = .zero
        }

        return AdvanceReport(
            suppliedElapsed: elapsed,
            consumedElapsed: clampedElapsed,
            executedTicks: executedTicks,
            discardedTicks: discardedTicks,
            remainingElapsed: accumulatedElapsed
        )
    }

    private mutating func clearTimingAndInput() {
        accumulatedElapsed = .zero
        heldInput = nil
        pendingRawInputs.removeAll(keepingCapacity: true)
    }
}
