import Foundation
import GameRealtimeProtocolKit
import GameRealtimeSimulationKit
import GameRealtimeStateKit

public struct OutboundSnapshotQueue: Sendable {
    public let limit: Int
    public private(set) var snapshots: [CanonicalSnapshot]

    public init(limit: Int = RealtimeLimits.standardV1.outboundSnapshots) {
        self.limit = limit
        snapshots = []
    }

    @discardableResult
    public mutating func enqueueCoalescing(
        _ snapshot: CanonicalSnapshot
    ) -> Bool {
        guard limit > 0 else {
            return true
        }
        if snapshots.count < limit {
            snapshots.append(snapshot)
            return false
        }
        snapshots[snapshots.count - 1] = snapshot
        return true
    }

    public var latest: CanonicalSnapshot? {
        snapshots.last
    }
}

public struct AuthorityQueues: Sendable {
    public let limits: RealtimeLimits
    public private(set) var inputFrames: [CombatInputFrame]
    public private(set) var events: [Data]
    public private(set) var outboundSnapshots: OutboundSnapshotQueue

    public init(limits: RealtimeLimits = .standardV1) {
        self.limits = limits
        inputFrames = []
        events = []
        outboundSnapshots = OutboundSnapshotQueue(
            limit: limits.outboundSnapshots
        )
    }

    public mutating func enqueueInput(_ input: CombatInputFrame) throws {
        let attempted = inputFrames.count + 1
        guard attempted <= limits.queuedInputFrames else {
            throw EngineCapacityError(
                resource: .queuedInputFrames,
                limit: limits.queuedInputFrames,
                attempted: attempted
            )
        }
        inputFrames.append(input)
    }

    public mutating func enqueueEvent(_ event: Data) throws {
        let attempted = events.count + 1
        guard attempted <= limits.authorityEventsPerTick else {
            throw EngineCapacityError(
                resource: .authorityEventsPerTick,
                limit: limits.authorityEventsPerTick,
                attempted: attempted
            )
        }
        events.append(event)
    }

    @discardableResult
    public mutating func enqueueOutbound(
        _ snapshot: CanonicalSnapshot
    ) -> Bool {
        outboundSnapshots.enqueueCoalescing(snapshot)
    }

    fileprivate func checkpointByteCount(base: Int) throws -> Int {
        var count = base
        for event in events {
            let (attempted, overflow) = count.addingReportingOverflow(
                event.count
            )
            guard !overflow,
                  attempted <= limits.canonicalSnapshotBytes
            else {
                throw EngineCapacityError(
                    resource: .canonicalSnapshotBytes,
                    limit: limits.canonicalSnapshotBytes,
                    attempted: overflow ? .max : attempted
                )
            }
            count = attempted
        }
        return count
    }
}

public struct TickAuthorityState: Sendable {
    public var world: CanonicalWorldState
    public var entities: EntityStore
    public var cacheVersion: UInt64
    public var eventOrdinal: UInt64

    public init(
        world: CanonicalWorldState,
        entities: EntityStore,
        cacheVersion: UInt64 = 0,
        eventOrdinal: UInt64 = 0
    ) {
        self.world = world
        self.entities = entities
        self.cacheVersion = cacheVersion
        self.eventOrdinal = eventOrdinal
    }
}

fileprivate struct RetainedAuthorityPayload: Sendable {
    let state: TickAuthorityState
    let rng: [RNGStreamID: DeterministicRNG]
    let queues: AuthorityQueues
}

private struct RetainedByteAccumulator {
    let limit: Int
    private(set) var total = 0

    mutating func add(_ bytes: Int) throws {
        guard bytes >= 0 else {
            throw capacityError(attempted: .max)
        }
        let (attempted, overflow) = total.addingReportingOverflow(bytes)
        guard !overflow, attempted <= limit else {
            throw capacityError(attempted: overflow ? .max : attempted)
        }
        total = attempted
    }

    mutating func add(count: Int, each bytes: Int) throws {
        guard count >= 0, bytes >= 0 else {
            throw capacityError(attempted: .max)
        }
        let (additional, overflow) = count.multipliedReportingOverflow(
            by: bytes
        )
        guard !overflow else {
            throw capacityError(attempted: .max)
        }
        try add(additional)
    }

    private func capacityError(attempted: Int) -> EngineCapacityError {
        EngineCapacityError(
            resource: .checkpointRingBytes,
            limit: limit,
            attempted: attempted
        )
    }
}

private enum RetainedAuthorityByteEstimator {
    private static let collectionOverhead = 24
    private static let stringOverhead = 16
    private static let dataOverhead = 24
    private static let dictionaryElementOverhead = 16
    private static let entityComponentBytes = 40
    private static let inputFrameBytes = 56
    private static let intBytes = 8
    private static let uint64Bytes = 8
    private static let entityHandleBytes = 8
    private static let componentKindBytes = 4

    static func estimate(
        state: TickAuthorityState,
        rng: [RNGStreamID: DeterministicRNG],
        queues: AuthorityQueues,
        snapshot: CanonicalSnapshot
    ) throws -> Int {
        var bytes = RetainedByteAccumulator(
            limit: queues.limits.checkpointRingBytes
        )

        try add(snapshot: snapshot, to: &bytes)
        try bytes.add(3 * uint64Bytes)
        try add(entityStore: state.entities, to: &bytes)
        try bytes.add(2 * uint64Bytes)

        try bytes.add(collectionOverhead)
        try bytes.add(
            count: rng.count,
            each: (2 * uint64Bytes) + dictionaryElementOverhead
        )

        try bytes.add(RealtimeLimitsFieldCount.value * intBytes)
        try bytes.add(collectionOverhead)
        try bytes.add(
            count: queues.inputFrames.count,
            each: inputFrameBytes
        )

        try bytes.add(collectionOverhead)
        for event in queues.events {
            try bytes.add(dataOverhead)
            try bytes.add(event.count)
        }

        try bytes.add(intBytes)
        try bytes.add(collectionOverhead)
        for outbound in queues.outboundSnapshots.snapshots {
            try add(snapshot: outbound, to: &bytes)
        }

        return bytes.total
    }

    static func snapshotByteCount(
        _ snapshot: CanonicalSnapshot,
        limit: Int
    ) throws -> Int {
        var bytes = RetainedByteAccumulator(limit: limit)
        try add(snapshot: snapshot, to: &bytes)
        return bytes.total
    }

    private static func add(
        snapshot: CanonicalSnapshot,
        to bytes: inout RetainedByteAccumulator
    ) throws {
        try bytes.add(3 * uint64Bytes)
        try bytes.add(2 * stringOverhead)
        try bytes.add(snapshot.schemaID.utf8.count)
        try bytes.add(snapshot.profileID.utf8.count)
        try bytes.add(collectionOverhead)
        try bytes.add(
            count: snapshot.rngStreams.count,
            each: 2 * uint64Bytes
        )
        try bytes.add(dataOverhead)
        try bytes.add(snapshot.canonicalBytes.count)
    }

    private static func add(
        entityStore: EntityStore,
        to bytes: inout RetainedByteAccumulator
    ) throws {
        let limits = entityStore.limits
        let liveEntityCount = entityStore.queryAll().count
        let structureCount = Int(
            min(entityStore.structureVersion, UInt64(Int.max))
        )
        let allocatedSlotEstimate = min(
            limits.totalEntities,
            max(liveEntityCount, structureCount)
        )
        let registeredKindEstimate = min(
            limits.registeredComponentKinds,
            structureCount
        )
        let (aggregateComponentCapacity, componentCapacityOverflow) =
            limits.componentSlotsPerKind.multipliedReportingOverflow(
                by: max(1, registeredKindEstimate)
            )
        let componentEntryEstimate = min(
            structureCount,
            componentCapacityOverflow ? .max : aggregateComponentCapacity
        )

        try bytes.add(RealtimeLimitsFieldCount.value * intBytes)
        try bytes.add(uint64Bytes)

        try bytes.add(8 * collectionOverhead)
        try bytes.add(count: allocatedSlotEstimate, each: 4)
        try bytes.add(count: allocatedSlotEstimate, each: 1)
        try bytes.add(count: allocatedSlotEstimate, each: 4)
        try bytes.add(
            count: registeredKindEstimate,
            each: componentKindBytes
        )
        try bytes.add(
            count: registeredKindEstimate,
            each: collectionOverhead + componentKindBytes
        )
        try bytes.add(
            count: componentEntryEstimate,
            each: entityComponentBytes
        )

        try bytes.add(uint64Bytes + collectionOverhead)
        try bytes.add(
            count: liveEntityCount,
            each: entityHandleBytes
        )

        var queryEntryBytes = RetainedByteAccumulator(limit: bytes.limit)
        try queryEntryBytes.add((2 * collectionOverhead) + uint64Bytes)
        try queryEntryBytes.add(
            count: registeredKindEstimate,
            each: componentKindBytes
        )
        try queryEntryBytes.add(
            count: liveEntityCount,
            each: entityHandleBytes
        )
        try bytes.add(
            count: limits.stableQueryCacheEntries,
            each: queryEntryBytes.total
        )
    }

    private enum RealtimeLimitsFieldCount {
        static let value = 17
    }
}

public enum TickFailureKind: Equatable, Sendable {
    case fixedPointOverflow
    case commandConflict
    case capacity(EngineCapacityError)
    case corruptRestore
    case other(String)
}

public struct EngineFaultDiagnostic: Equatable, Sendable {
    public let tick: UInt64
    public let failure: TickFailureKind
    public let consecutiveCapacityFailures: Int

    public init(
        tick: UInt64,
        failure: TickFailureKind,
        consecutiveCapacityFailures: Int
    ) {
        self.tick = tick
        self.failure = failure
        self.consecutiveCapacityFailures = consecutiveCapacityFailures
    }
}

public enum EngineFault: Equatable, Sendable {
    case repeatedCapacityFailure(
        lastValidSnapshot: CanonicalSnapshot,
        diagnostic: EngineFaultDiagnostic
    )
    case corruptRestore(
        lastValidSnapshot: CanonicalSnapshot,
        diagnostic: EngineFaultDiagnostic
    )
}

public enum TickTransactionError: Error, Equatable, Sendable {
    case faulted
}

public struct CheckpointRing: Sendable {
    public struct Entry: Sendable {
        public let snapshot: CanonicalSnapshot
        public let byteCount: Int
        private let retainedAuthority: RetainedAuthorityPayload?

        public init(snapshot: CanonicalSnapshot, byteCount: Int) {
            self.snapshot = snapshot
            self.byteCount = byteCount
            retainedAuthority = nil
        }

        fileprivate init(
            snapshot: CanonicalSnapshot,
            byteCount: Int,
            retainedAuthority: RetainedAuthorityPayload
        ) {
            self.snapshot = snapshot
            self.byteCount = byteCount
            self.retainedAuthority = retainedAuthority
        }
    }

    public let maxEntries: Int
    public let maxBytes: Int
    public private(set) var entries: [Entry]
    public private(set) var totalBytes: Int

    public init(
        maxEntries: Int = RealtimeLimits.standardV1.checkpointRingLength,
        maxBytes: Int = RealtimeLimits.standardV1.checkpointRingBytes
    ) {
        self.maxEntries = maxEntries
        self.maxBytes = maxBytes
        entries = []
        totalBytes = 0
    }

    public mutating func append(_ snapshot: CanonicalSnapshot) throws {
        let retainedBytes =
            try RetainedAuthorityByteEstimator.snapshotByteCount(
                snapshot,
                limit: maxBytes
            )
        try append(
            snapshot,
            accountedBytes: retainedBytes,
            retainedAuthority: nil
        )
    }

    public mutating func append(
        _ snapshot: CanonicalSnapshot,
        accountedBytes: Int
    ) throws {
        guard accountedBytes >= 0 else {
            throw EngineCapacityError(
                resource: .checkpointRingBytes,
                limit: maxBytes,
                attempted: .max
            )
        }
        let snapshotBytes =
            try RetainedAuthorityByteEstimator.snapshotByteCount(
                snapshot,
                limit: maxBytes
            )
        try append(
            snapshot,
            accountedBytes: max(accountedBytes, snapshotBytes),
            retainedAuthority: nil
        )
    }

    private mutating func append(
        _ snapshot: CanonicalSnapshot,
        accountedBytes: Int,
        retainedAuthority: RetainedAuthorityPayload?
    ) throws {
        guard maxEntries > 0 else {
            throw EngineCapacityError(
                resource: .checkpointRingLength,
                limit: maxEntries,
                attempted: 1
            )
        }
        guard accountedBytes >= 0,
              accountedBytes <= maxBytes
        else {
            throw EngineCapacityError(
                resource: .checkpointRingBytes,
                limit: maxBytes,
                attempted: accountedBytes < 0 ? .max : accountedBytes
            )
        }

        var candidateEntries = entries
        var candidateBytes = totalBytes

        while candidateEntries.count >= maxEntries {
            candidateBytes -= candidateEntries.removeFirst().byteCount
        }
        while true {
            let (attemptedBytes, overflow) =
                candidateBytes.addingReportingOverflow(accountedBytes)
            if !overflow, attemptedBytes <= maxBytes {
                candidateBytes = attemptedBytes
                break
            }
            guard !candidateEntries.isEmpty else {
                throw EngineCapacityError(
                    resource: .checkpointRingBytes,
                    limit: maxBytes,
                    attempted: overflow ? .max : attemptedBytes
                )
            }
            candidateBytes -= candidateEntries.removeFirst().byteCount
        }

        if let retainedAuthority {
            candidateEntries.append(
                Entry(
                    snapshot: snapshot,
                    byteCount: accountedBytes,
                    retainedAuthority: retainedAuthority
                )
            )
        } else {
            candidateEntries.append(
                Entry(snapshot: snapshot, byteCount: accountedBytes)
            )
        }
        entries = candidateEntries
        totalBytes = candidateBytes
    }

    fileprivate mutating func append(
        _ checkpoint: TickTransaction.Checkpoint
    ) throws {
        try append(
            checkpoint.snapshot,
            accountedBytes: checkpoint.byteCount,
            retainedAuthority: checkpoint.retainedAuthority
        )
    }
}

public struct TickTransaction: Sendable {
    fileprivate struct Checkpoint: Sendable {
        let state: TickAuthorityState
        let rng: [RNGStreamID: DeterministicRNG]
        let queues: AuthorityQueues
        let snapshot: CanonicalSnapshot
        let byteCount: Int
        let retainedAuthority: RetainedAuthorityPayload
    }

    public var state: TickAuthorityState
    public var rng: [RNGStreamID: DeterministicRNG]
    public var queues: AuthorityQueues
    public private(set) var checkpointRing: CheckpointRing
    public private(set) var lastValidSnapshot: CanonicalSnapshot
    public private(set) var lastDiagnostic: EngineFaultDiagnostic?
    public private(set) var fault: EngineFault?

    private let codec: CanonicalSnapshotCodec
    private let capacityFailureThreshold: Int
    private var tickStart: Checkpoint
    private var consecutiveCapacityFailures: Int

    public static func begin(
        state: TickAuthorityState,
        rng: [RNGStreamID: DeterministicRNG],
        queues: AuthorityQueues,
        codec: CanonicalSnapshotCodec = CanonicalSnapshotCodec(profile: .v1),
        capacityFailureThreshold: Int = 3
    ) throws -> TickTransaction {
        let checkpoint = try makeCheckpoint(
            state: state,
            rng: rng,
            queues: queues,
            codec: codec
        )
        var ring = CheckpointRing(
            maxEntries: queues.limits.checkpointRingLength,
            maxBytes: queues.limits.checkpointRingBytes
        )
        try ring.append(checkpoint)
        return TickTransaction(
            state: state,
            rng: rng,
            queues: queues,
            checkpointRing: ring,
            lastValidSnapshot: checkpoint.snapshot,
            lastDiagnostic: nil,
            fault: nil,
            codec: codec,
            capacityFailureThreshold: max(1, capacityFailureThreshold),
            tickStart: checkpoint,
            consecutiveCapacityFailures: 0
        )
    }

    public mutating func performTick(
        _ mutation: (
            inout TickAuthorityState,
            inout [RNGStreamID: DeterministicRNG],
            inout AuthorityQueues
        ) throws -> Void
    ) throws {
        guard fault == nil else {
            throw TickTransactionError.faulted
        }
        tickStart = try Self.makeCheckpoint(
            state: state,
            rng: rng,
            queues: queues,
            codec: codec
        )

        do {
            try mutation(&state, &rng, &queues)
            try commitCandidate()
        } catch {
            rollback()
            recordFailure(error)
            throw error
        }
    }

    public mutating func commit() throws {
        guard fault == nil else {
            throw TickTransactionError.faulted
        }
        do {
            try commitCandidate()
        } catch {
            rollback()
            recordFailure(error)
            throw error
        }
    }

    public mutating func rollback() {
        state = tickStart.state
        rng = tickStart.rng
        queues = tickStart.queues
    }

    public mutating func restore(_ snapshot: CanonicalSnapshot) throws {
        let originalState = state
        let originalRNG = rng
        let originalQueues = queues
        var candidateWorld = state.world
        var candidateRNG = rng

        do {
            try codec.restore(
                snapshot,
                state: &candidateWorld,
                rng: &candidateRNG
            )
            var candidateState = state
            candidateState.world = candidateWorld
            let checkpoint = try Self.makeCheckpoint(
                state: candidateState,
                rng: candidateRNG,
                queues: queues,
                codec: codec
            )
            var candidateRing = checkpointRing
            try candidateRing.append(checkpoint)
            state = candidateState
            rng = candidateRNG
            checkpointRing = candidateRing
            tickStart = checkpoint
            lastValidSnapshot = checkpoint.snapshot
            consecutiveCapacityFailures = 0
            lastDiagnostic = nil
            fault = nil
        } catch {
            state = originalState
            rng = originalRNG
            queues = originalQueues
            let diagnostic = EngineFaultDiagnostic(
                tick: originalState.world.tick,
                failure: .corruptRestore,
                consecutiveCapacityFailures: consecutiveCapacityFailures
            )
            lastDiagnostic = diagnostic
            fault = .corruptRestore(
                lastValidSnapshot: lastValidSnapshot,
                diagnostic: diagnostic
            )
            throw error
        }
    }

    private mutating func commitCandidate() throws {
        let checkpoint = try Self.makeCheckpoint(
            state: state,
            rng: rng,
            queues: queues,
            codec: codec
        )
        var candidateRing = checkpointRing
        try candidateRing.append(checkpoint)

        checkpointRing = candidateRing
        tickStart = checkpoint
        lastValidSnapshot = checkpoint.snapshot
        consecutiveCapacityFailures = 0
        lastDiagnostic = nil
    }

    private mutating func recordFailure(_ error: any Error) {
        let failure = Self.failureKind(for: error)
        if case .capacity = failure {
            consecutiveCapacityFailures += 1
        } else {
            consecutiveCapacityFailures = 0
        }
        let diagnostic = EngineFaultDiagnostic(
            tick: tickStart.state.world.tick,
            failure: failure,
            consecutiveCapacityFailures: consecutiveCapacityFailures
        )
        lastDiagnostic = diagnostic
        if consecutiveCapacityFailures >= capacityFailureThreshold {
            fault = .repeatedCapacityFailure(
                lastValidSnapshot: lastValidSnapshot,
                diagnostic: diagnostic
            )
        }
    }

    private static func failureKind(for error: any Error) -> TickFailureKind {
        if let capacity = error as? EngineCapacityError {
            return .capacity(capacity)
        }
        if error is FixedPointError {
            return .fixedPointOverflow
        }
        if let command = error as? DeferredCommandError {
            switch command {
            case .conflictingMutations, .duplicateKey:
                return .commandConflict
            case .invalidCommandLimit, .staleHandle:
                return .other(String(reflecting: type(of: error)))
            }
        }
        if error is SnapshotRestoreError {
            return .corruptRestore
        }
        return .other(String(reflecting: type(of: error)))
    }

    private static func makeCheckpoint(
        state: TickAuthorityState,
        rng: [RNGStreamID: DeterministicRNG],
        queues: AuthorityQueues,
        codec: CanonicalSnapshotCodec
    ) throws -> Checkpoint {
        let snapshot = try codec.encode(state: state.world, rng: rng)
        _ = try queues.checkpointByteCount(
            base: snapshot.canonicalBytes.count
        )
        let byteCount = try RetainedAuthorityByteEstimator.estimate(
            state: state,
            rng: rng,
            queues: queues,
            snapshot: snapshot
        )
        let retainedAuthority = RetainedAuthorityPayload(
            state: state,
            rng: rng,
            queues: queues
        )
        return Checkpoint(
            state: state,
            rng: rng,
            queues: queues,
            snapshot: snapshot,
            byteCount: byteCount,
            retainedAuthority: retainedAuthority
        )
    }
}
