import Foundation
import GameRealtimeProtocolKit
import GameRealtimeRuntimeKit
import GameRealtimeSimulationKit
import GameRealtimeStateKit
import XCTest

final class TickTransactionTests: XCTestCase {
    func testCapacityFailureRollsBackEveryAuthorityValue() throws {
        var transaction = try makeTransaction()
        let start = authoritySignature(transaction)
        let capacity = EngineCapacityError(
            resource: .deferredCommandsPerTick,
            limit: RealtimeLimits.standardV1.deferredCommandsPerTick,
            attempted: RealtimeLimits.standardV1.deferredCommandsPerTick + 1
        )

        for failureNumber in 1 ... 3 {
            XCTAssertThrowsError(
                try transaction.performTick { state, rng, queues in
                    state.world.tick = 99
                    state.world.epoch = 88
                    _ = try state.entities.spawn()
                    state.cacheVersion = 77
                    state.eventOrdinal = 66
                    _ = rng[.simulation]?.next()
                    try queues.enqueueEvent(Data([9, 9, 9]))
                    throw capacity
                }
            ) { error in
                XCTAssertEqual(error as? EngineCapacityError, capacity)
            }
            XCTAssertEqual(authoritySignature(transaction), start)
            XCTAssertEqual(
                transaction.lastDiagnostic?.consecutiveCapacityFailures,
                failureNumber
            )
        }

        guard case let .repeatedCapacityFailure(snapshot, diagnostic) =
            transaction.fault
        else {
            return XCTFail("expected repeated-capacity fault")
        }
        XCTAssertEqual(snapshot, transaction.lastValidSnapshot)
        XCTAssertEqual(snapshot.tick, 10)
        XCTAssertEqual(diagnostic.failure, .capacity(capacity))
        XCTAssertEqual(diagnostic.consecutiveCapacityFailures, 3)
    }

    func testEveryCapacityKindAndSimulationFailureRollsBack() throws {
        let limits = RealtimeLimits.standardV1
        let capacities: [(EngineCapacityError.Resource, Int)] = [
            (.entities, limits.totalEntities),
            (.entitiesPerKind, limits.entitiesPerKind),
            (.componentSlotsPerKind, limits.componentSlotsPerKind),
            (.registeredComponentKinds, limits.registeredComponentKinds),
            (.stableQueryCacheEntries, limits.stableQueryCacheEntries),
            (.deferredCommandsPerTick, limits.deferredCommandsPerTick),
            (.authorityEventsPerTick, limits.authorityEventsPerTick),
            (.queuedInputFrames, limits.queuedInputFrames),
            (.broadphaseOccupiedCells, limits.broadphaseOccupiedCells),
            (
                .broadphaseCandidatePairsPerTick,
                limits.broadphaseCandidatePairsPerTick
            ),
            (
                .resolvedCollisionPairsPerTick,
                limits.resolvedCollisionPairsPerTick
            ),
            (.solverIterationsPerPair, limits.solverIterationsPerPair),
            (.checkpointRingLength, limits.checkpointRingLength),
            (.checkpointRingBytes, limits.checkpointRingBytes),
            (.canonicalSnapshotBytes, limits.canonicalSnapshotBytes),
            (.replayInputFrames, limits.replayInputFrames),
            (.outboundSnapshots, limits.outboundSnapshots),
        ]

        for (resource, limit) in capacities {
            var transaction = try makeTransaction()
            let start = authoritySignature(transaction)
            let expected = EngineCapacityError(
                resource: resource,
                limit: limit,
                attempted: limit + 1
            )
            XCTAssertThrowsError(
                try transaction.performTick { state, _, _ in
                    state.world.tick += 1
                    state.cacheVersion += 1
                    throw expected
                }
            ) { error in
                XCTAssertEqual(error as? EngineCapacityError, expected)
            }
            XCTAssertEqual(authoritySignature(transaction), start)
        }

        for failure in [
            FixedPointError.overflow as any Error,
            DeferredCommandError.conflictingMutations(
                EntityHandle(index: 0, generation: 1)
            ) as any Error,
        ] {
            var transaction = try makeTransaction()
            let start = authoritySignature(transaction)
            XCTAssertThrowsError(
                try transaction.performTick { state, _, _ in
                    state.world.tick += 1
                    throw failure
                }
            )
            XCTAssertEqual(authoritySignature(transaction), start)
            XCTAssertNil(transaction.fault)
        }
    }

    func testSnapshotOverflowAndCorruptRestoreAreAtomic() throws {
        var overflowTransaction = try makeTransaction()
        let overflowStart = authoritySignature(overflowTransaction)
        XCTAssertThrowsError(
            try overflowTransaction.performTick { state, _, queues in
                state.world.tick += 1
                try queues.enqueueEvent(
                    Data(
                        repeating: 7,
                        count: RealtimeLimits.standardV1.canonicalSnapshotBytes
                    )
                )
            }
        ) { error in
            guard let capacity = error as? EngineCapacityError else {
                return XCTFail("expected canonical snapshot capacity error")
            }
            XCTAssertEqual(capacity.resource, .canonicalSnapshotBytes)
            XCTAssertEqual(
                capacity.limit,
                RealtimeLimits.standardV1.canonicalSnapshotBytes
            )
            XCTAssertGreaterThan(capacity.attempted, capacity.limit)
        }
        XCTAssertEqual(authoritySignature(overflowTransaction), overflowStart)

        var restoreTransaction = try makeTransaction()
        let restoreStart = authoritySignature(restoreTransaction)
        let valid = restoreTransaction.lastValidSnapshot
        var corruptedBytes = valid.canonicalBytes
        corruptedBytes[corruptedBytes.startIndex] ^= 0xFF
        let corrupted = try CanonicalSnapshot(
            schemaID: valid.schemaID,
            profileID: valid.profileID,
            tick: valid.tick,
            epoch: valid.epoch,
            rngStreams: valid.rngStreams,
            canonicalBytes: corruptedBytes,
            deterministicStateHash: valid.deterministicStateHash
        )

        XCTAssertThrowsError(try restoreTransaction.restore(corrupted))
        XCTAssertEqual(authoritySignature(restoreTransaction), restoreStart)
        guard case let .corruptRestore(snapshot, diagnostic) =
            restoreTransaction.fault
        else {
            return XCTFail("expected corrupt-restore fault")
        }
        XCTAssertEqual(snapshot, valid)
        XCTAssertEqual(diagnostic.failure, .corruptRestore)
    }

    func testCheckpointRingLengthAndBytesAreAtomicAtBoundaries() throws {
        let first = try makeSnapshot(tick: 1, bytes: 1)
        let second = try makeSnapshot(tick: 2, bytes: 1)
        let third = try makeSnapshot(tick: 3, bytes: 1)
        var sizeProbe = CheckpointRing(maxEntries: 1, maxBytes: 1_024)
        try sizeProbe.append(first)
        let retainedSnapshotBytes = sizeProbe.totalBytes

        var lengthRing = CheckpointRing(
            maxEntries: 2,
            maxBytes: retainedSnapshotBytes * 3
        )
        try lengthRing.append(first)
        XCTAssertEqual(lengthRing.entries.count, 1)
        try lengthRing.append(second)
        XCTAssertEqual(lengthRing.entries.count, 2)
        XCTAssertEqual(
            lengthRing.totalBytes,
            retainedSnapshotBytes * 2
        )

        try lengthRing.append(third)
        XCTAssertEqual(lengthRing.entries.count, 2)
        XCTAssertEqual(
            lengthRing.totalBytes,
            retainedSnapshotBytes * 2
        )
        XCTAssertEqual(lengthRing.entries.map(\.snapshot.tick), [2, 3])

        let byteBudget = retainedSnapshotBytes * 2
        var byteRing = CheckpointRing(
            maxEntries: 3,
            maxBytes: byteBudget
        )
        try byteRing.append(first)
        try byteRing.append(second)
        XCTAssertEqual(byteRing.totalBytes, byteBudget)
        try byteRing.append(third)
        XCTAssertEqual(byteRing.entries.map(\.snapshot.tick), [2, 3])
        XCTAssertEqual(byteRing.totalBytes, byteBudget)

        let oversized = try makeSnapshot(
            tick: 4,
            bytes: byteBudget + 1
        )
        XCTAssertThrowsError(
            try byteRing.append(oversized)
        ) { error in
            guard let capacity = error as? EngineCapacityError else {
                return XCTFail("expected checkpoint byte capacity error")
            }
            XCTAssertEqual(capacity.resource, .checkpointRingBytes)
            XCTAssertEqual(capacity.limit, byteBudget)
            XCTAssertGreaterThan(capacity.attempted, byteBudget)
        }
        XCTAssertEqual(byteRing.entries.count, 2)
        XCTAssertEqual(byteRing.totalBytes, byteBudget)

        var transaction = try makeTransaction()
        for _ in 0 ..< 10_000 {
            try transaction.performTick { state, _, _ in
                state.world.tick += 1
            }
        }
        XCTAssertEqual(transaction.state.world.tick, 10_010)
        XCTAssertLessThanOrEqual(
            transaction.checkpointRing.entries.count,
            RealtimeLimits.standardV1.checkpointRingLength
        )
        XCTAssertLessThanOrEqual(
            transaction.checkpointRing.totalBytes,
            RealtimeLimits.standardV1.checkpointRingBytes
        )

        XCTAssertEqual(
            RealtimeLimits.standardV1.checkpointRingLength,
            120
        )
        XCTAssertEqual(
            RealtimeLimits.standardV1.checkpointRingBytes,
            67_108_864
        )
        XCTAssertEqual(
            RealtimeLimits.standardV1.canonicalSnapshotBytes,
            524_288
        )
    }

    func testRetainedByteAccountingIncludesEveryAuthorityField() throws {
        let baseline = try makeAccountingTransaction()
        let baselineBytes = try XCTUnwrap(
            baseline.checkpointRing.entries.last?.byteCount
        )

        var entities = try EntityStore(limits: .standardV1)
        _ = try entities.spawn()
        let entityPayload = try makeAccountingTransaction(entities: entities)
        XCTAssertGreaterThan(
            try XCTUnwrap(entityPayload.checkpointRing.entries.last?.byteCount),
            baselineBytes
        )

        var inputQueues = AuthorityQueues()
        try inputQueues.enqueueInput(makeInput(sequence: 1))
        let inputPayload = try makeAccountingTransaction(queues: inputQueues)
        XCTAssertGreaterThan(
            try XCTUnwrap(inputPayload.checkpointRing.entries.last?.byteCount),
            baselineBytes
        )

        var eventQueues = AuthorityQueues()
        try eventQueues.enqueueEvent(Data(repeating: 1, count: 64))
        let eventPayload = try makeAccountingTransaction(queues: eventQueues)
        XCTAssertGreaterThan(
            try XCTUnwrap(eventPayload.checkpointRing.entries.last?.byteCount),
            baselineBytes + 64
        )

        var outboundQueues = AuthorityQueues()
        outboundQueues.enqueueOutbound(
            try makeSnapshot(tick: 2, bytes: 64)
        )
        let outboundPayload = try makeAccountingTransaction(
            queues: outboundQueues
        )
        XCTAssertGreaterThan(
            try XCTUnwrap(
                outboundPayload.checkpointRing.entries.last?.byteCount
            ),
            baselineBytes
        )

        let rngPayload = try makeAccountingTransaction(
            rng: [
                .simulation: DeterministicRNG(seed: 1),
                .combat: DeterministicRNG(seed: 2),
            ]
        )
        XCTAssertGreaterThan(
            try XCTUnwrap(rngPayload.checkpointRing.entries.last?.byteCount),
            baselineBytes
        )

        let scalarPayload = try makeAccountingTransaction(
            cacheVersion: 99,
            eventOrdinal: 101
        )
        XCTAssertEqual(
            scalarPayload.checkpointRing.entries.last?.byteCount,
            baselineBytes
        )
        XCTAssertGreaterThanOrEqual(
            baselineBytes,
            baseline.lastValidSnapshot.canonicalBytes.count
                + (5 * MemoryLayout<UInt64>.size)
        )

        let tightLimits = makeLimits(checkpointRingBytes: baselineBytes)
        var tightTransaction = try makeAccountingTransaction(
            queues: AuthorityQueues(limits: tightLimits)
        )
        let ringBeforeFailure = tightTransaction.checkpointRing
        XCTAssertThrowsError(
            try tightTransaction.performTick { _, _, queues in
                try queues.enqueueInput(self.makeInput(sequence: 2))
            }
        ) { error in
            guard let capacity = error as? EngineCapacityError else {
                return XCTFail("expected checkpoint byte capacity error")
            }
            XCTAssertEqual(capacity.resource, .checkpointRingBytes)
            XCTAssertEqual(capacity.limit, baselineBytes)
            XCTAssertGreaterThan(capacity.attempted, baselineBytes)
        }
        XCTAssertTrue(tightTransaction.queues.inputFrames.isEmpty)
        XCTAssertEqual(
            tightTransaction.checkpointRing.entries.map(\.snapshot),
            ringBeforeFailure.entries.map(\.snapshot)
        )
        XCTAssertEqual(
            tightTransaction.checkpointRing.totalBytes,
            ringBeforeFailure.totalBytes
        )
    }

    func testOutboundSnapshotsCoalesceAtEightWithoutBlocking() throws {
        var queue = OutboundSnapshotQueue()
        for tick in 1 ... RealtimeLimits.standardV1.outboundSnapshots {
            XCTAssertFalse(
                queue.enqueueCoalescing(
                    try makeSnapshot(tick: UInt64(tick), bytes: 1)
                )
            )
        }
        XCTAssertEqual(queue.snapshots.count, 8)
        XCTAssertEqual(queue.snapshots.map(\.tick), Array(1 ... 8).map(UInt64.init))

        XCTAssertTrue(
            queue.enqueueCoalescing(try makeSnapshot(tick: 9, bytes: 1))
        )
        XCTAssertEqual(queue.snapshots.count, 8)
        XCTAssertEqual(queue.snapshots.map(\.tick), [1, 2, 3, 4, 5, 6, 7, 9])
        XCTAssertEqual(queue.latest?.tick, 9)
    }

    private func makeTransaction() throws -> TickTransaction {
        var entities = try EntityStore(limits: .standardV1)
        _ = try entities.spawn()
        let state = TickAuthorityState(
            world: CanonicalWorldState(tick: 10, epoch: 3, seed: 42),
            entities: entities,
            cacheVersion: 5,
            eventOrdinal: 7
        )
        var queues = AuthorityQueues()
        try queues.enqueueEvent(Data([1, 2, 3]))
        return try TickTransaction.begin(
            state: state,
            rng: [
                .simulation: DeterministicRNG(seed: 11),
                .combat: DeterministicRNG(seed: 22),
            ],
            queues: queues
        )
    }

    private func makeAccountingTransaction(
        entities: EntityStore? = nil,
        rng: [RNGStreamID: DeterministicRNG] = [
            .simulation: DeterministicRNG(seed: 1),
        ],
        queues: AuthorityQueues = AuthorityQueues(),
        cacheVersion: UInt64 = 0,
        eventOrdinal: UInt64 = 0
    ) throws -> TickTransaction {
        let store: EntityStore
        if let entities {
            store = entities
        } else {
            store = try EntityStore(limits: .standardV1)
        }
        return try TickTransaction.begin(
            state: TickAuthorityState(
                world: CanonicalWorldState(seed: 1),
                entities: store,
                cacheVersion: cacheVersion,
                eventOrdinal: eventOrdinal
            ),
            rng: rng,
            queues: queues
        )
    }

    private func makeInput(sequence: UInt64) throws -> CombatInputFrame {
        try CombatInputFrame(
            targetTick: 1,
            controlledEntity: EntityHandle(index: 0, generation: 1),
            sequence: sequence,
            source: .manual,
            move: FixedVector2(
                x: FixedPoint(rawValue: 0),
                y: FixedPoint(rawValue: 0)
            ),
            aim: FixedVector2(
                x: FixedPoint(rawValue: 0),
                y: FixedPoint(rawValue: 0)
            ),
            buttons: []
        )
    }

    private func makeLimits(checkpointRingBytes: Int) -> RealtimeLimits {
        return RealtimeLimits.standardV1.withPersistence(
            checkpointRingBytes: checkpointRingBytes
        )
    }

    private func authoritySignature(
        _ transaction: TickTransaction
    ) -> AuthoritySignature {
        AuthoritySignature(
            tick: transaction.state.world.tick,
            epoch: transaction.state.world.epoch,
            seed: transaction.state.world.seed,
            entities: transaction.state.entities.queryAll(),
            structureVersion: transaction.state.entities.structureVersion,
            simulationRNG: transaction.rng[.simulation]?.state,
            combatRNG: transaction.rng[.combat]?.state,
            inputFrames: transaction.queues.inputFrames,
            events: transaction.queues.events,
            outbound: transaction.queues.outboundSnapshots.snapshots,
            cacheVersion: transaction.state.cacheVersion,
            eventOrdinal: transaction.state.eventOrdinal
        )
    }

    private func makeSnapshot(
        tick: UInt64,
        bytes: Int
    ) throws -> CanonicalSnapshot {
        try CanonicalSnapshot(
            schemaID: "test",
            profileID: "test",
            tick: tick,
            epoch: 0,
            rngStreams: [],
            canonicalBytes: Data(repeating: 0, count: bytes),
            deterministicStateHash: 0
        )
    }
}

private struct AuthoritySignature: Equatable {
    let tick: UInt64
    let epoch: UInt64
    let seed: UInt64
    let entities: [EntityHandle]
    let structureVersion: UInt64
    let simulationRNG: UInt64?
    let combatRNG: UInt64?
    let inputFrames: [CombatInputFrame]
    let events: [Data]
    let outbound: [CanonicalSnapshot]
    let cacheVersion: UInt64
    let eventOrdinal: UInt64
}
