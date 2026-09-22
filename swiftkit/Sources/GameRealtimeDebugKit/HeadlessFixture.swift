#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import Foundation
import GameRealtimeEngineKit
import GameRealtimeProtocolKit
import GameRealtimeRuntimeKit
import GameRealtimeSimulationKit
import GameRealtimeStateKit

public enum HeadlessInputMode: Sendable {
    case manual
    case automatic
}

enum HeadlessFixtureError: Error, Equatable, Sendable {
    case negativeTickCount(Int)
    case inputSequenceOverflow
    case tickOverflow
    case eventOrdinalOverflow
    case unqualifiedBenchmarkFixture
    case memoryMeasurementFailed(Int32)
}

public struct HeadlessFixture: @unchecked Sendable {
    private let storage: HeadlessFixtureStorage

    public init(
        configuration: GameRealtimeConfiguration,
        inputMode: HeadlessInputMode
    ) throws {
        storage = try HeadlessFixtureStorage(
            configuration: configuration,
            inputMode: inputMode,
            manifest: nil
        )
    }

    init(
        configuration: GameRealtimeConfiguration,
        inputMode: HeadlessInputMode,
        qualified manifest: BenchmarkFixtureManifest
    ) throws {
        storage = try HeadlessFixtureStorage(
            configuration: configuration,
            inputMode: inputMode,
            manifest: manifest
        )
    }

    public func spawnGroundLoot(
        at position: FixedVector2
    ) throws -> EntityHandle {
        try storage.withLock {
            var spawned: EntityHandle?
            try storage.transaction.performTick { state, _, _ in
                let entity = try state.entities.spawn()
                _ = try state.entities.attachComponent(
                    .unsigned(1),
                    kind: HeadlessFixtureStorage.groundLootKind,
                    to: entity
                )
                _ = try state.entities.attachComponent(
                    .vector(position),
                    kind: HeadlessFixtureStorage.positionKind,
                    to: entity
                )
                spawned = entity
            }
            guard let spawned else {
                throw HeadlessFixtureError.unqualifiedBenchmarkFixture
            }
            return spawned
        }
    }

    public func setHealth(
        _ value: Int32,
        for entity: EntityHandle
    ) throws {
        try storage.withLock {
            try storage.transaction.performTick { state, _, _ in
                if value <= 0 {
                    try state.entities.despawn(entity)
                } else {
                    _ = try state.entities.attachComponent(
                        .signed(value),
                        kind: HeadlessFixtureStorage.healthKind,
                        to: entity
                    )
                }
            }
        }
    }

    public func run(
        ticks: Int,
        input: CombatInputFrame
    ) throws -> DeterminismRunReport {
        try storage.withLock {
            try storage.run(ticks: ticks, input: input)
        }
    }

    func benchmarkSample(
        ticks: Int,
        input: CombatInputFrame,
        measureDurations: Bool
    ) throws -> HeadlessBenchmarkSample {
        try storage.withLock {
            try storage.benchmarkSample(
                ticks: ticks,
                input: input,
                measureDurations: measureDurations
            )
        }
    }

    func soak(
        ticks: Int,
        simulatedSeconds: Int,
        input: CombatInputFrame
    ) throws -> SoakRunReport {
        try storage.withLock {
            try storage.soak(
                ticks: ticks,
                simulatedSeconds: simulatedSeconds,
                input: input
            )
        }
    }
}

final class HeadlessFixtureStorage: @unchecked Sendable {
    static let groundLootKind = ComponentKind(rawValue: 1)
    static let positionKind = ComponentKind(rawValue: 2)
    static let healthKind = ComponentKind(rawValue: 3)

    let configuration: GameRealtimeConfiguration
    let inputMode: HeadlessInputMode
    let lock = NSLock()
    var transaction: TickTransaction
    private let qualifiedWorkload: QualifiedAuthorityWorkload?
    private var lastEvidence: QualifiedTickEvidence?
    private var lastCollisionWorld: CollisionWorld?

    init(
        configuration: GameRealtimeConfiguration,
        inputMode: HeadlessInputMode,
        manifest: BenchmarkFixtureManifest?
    ) throws {
        self.configuration = configuration
        self.inputMode = inputMode

        let entities: EntityStore
        if let manifest {
            let construction = try QualifiedAuthorityWorkload.make(
                manifest: manifest,
                limits: configuration.limits
            )
            entities = construction.entities
            qualifiedWorkload = construction.workload
        } else {
            var genericEntities = try EntityStore(
                limits: configuration.limits
            )
            try genericEntities.registerComponentKind(Self.groundLootKind)
            try genericEntities.registerComponentKind(Self.positionKind)
            try genericEntities.registerComponentKind(Self.healthKind)
            entities = genericEntities
            qualifiedWorkload = nil
        }

        let simulationRNG = DeterministicRNG(seed: 42)
        transaction = try TickTransaction.begin(
            state: TickAuthorityState(
                world: CanonicalWorldState(seed: 42),
                entities: entities
            ),
            rng: [
                .simulation: simulationRNG,
                .combat: simulationRNG.stream(.combat),
            ],
            queues: AuthorityQueues(limits: configuration.limits),
            codec: CanonicalSnapshotCodec(
                profile: configuration.determinism
            )
        )
        lastEvidence = nil
        lastCollisionWorld = nil
    }

    func withLock<Result>(
        _ operation: () throws -> Result
    ) rethrows -> Result {
        lock.lock()
        defer {
            lock.unlock()
        }
        return try operation()
    }

    func run(
        ticks: Int,
        input: CombatInputFrame
    ) throws -> DeterminismRunReport {
        guard ticks >= 0 else {
            throw HeadlessFixtureError.negativeTickCount(ticks)
        }
        for offset in 0 ..< ticks {
            try advanceGenericTick(
                input: resolvedInput(input, offset: offset)
            )
        }
        return DeterminismRunReport(
            ticks: ticks,
            snapshot: transaction.lastValidSnapshot
        )
    }

    func benchmarkSample(
        ticks: Int,
        input: CombatInputFrame,
        measureDurations: Bool
    ) throws -> HeadlessBenchmarkSample {
        guard ticks >= 0 else {
            throw HeadlessFixtureError.negativeTickCount(ticks)
        }
        guard qualifiedWorkload != nil else {
            throw HeadlessFixtureError.unqualifiedBenchmarkFixture
        }
        let clock = ContinuousClock()
        var durations: [UInt64] = []
        if measureDurations {
            durations.reserveCapacity(ticks)
        }
        var peakRSSBytes = try ProcessMemory.residentBytes()

        for offset in 0 ..< ticks {
            let start = clock.now
            try advanceQualifiedTick(
                input: resolvedInput(input, offset: offset)
            )
            if measureDurations {
                durations.append(
                    Self.nanoseconds(start.duration(to: clock.now))
                )
            }
            if (offset + 1).isMultiple(of: 600) {
                peakRSSBytes = max(
                    peakRSSBytes,
                    try ProcessMemory.residentBytes()
                )
            }
        }

        peakRSSBytes = max(
            peakRSSBytes,
            try ProcessMemory.residentBytes()
        )
        return HeadlessBenchmarkSample(
            tickNanoseconds: durations,
            snapshot: transaction.lastValidSnapshot,
            metrics: try qualifiedMetrics(),
            peakRSSBytes: peakRSSBytes
        )
    }

    func soak(
        ticks: Int,
        simulatedSeconds: Int,
        input: CombatInputFrame
    ) throws -> SoakRunReport {
        guard ticks >= 0 else {
            throw HeadlessFixtureError.negativeTickCount(ticks)
        }
        guard qualifiedWorkload != nil else {
            throw HeadlessFixtureError.unqualifiedBenchmarkFixture
        }
        let origin = ContinuousClock().now
        var manualClock = ManualGameRealtimeClock(startingAt: origin)
        var samples: [SoakMetricSample] = []
        samples.reserveCapacity(max(1, ticks / 600))

        for offset in 0 ..< ticks {
            try advanceQualifiedTick(
                input: resolvedInput(input, offset: offset)
            )
            try manualClock.advance(
                by: configuration.tickPolicy.fixedStep
            )
            if (offset + 1).isMultiple(of: 600) {
                let metrics = try qualifiedMetrics()
                samples.append(
                    SoakMetricSample(
                        tick: offset + 1,
                        entityCount: metrics.entityCount,
                        componentCount: metrics.componentCount,
                        queueCount: metrics.queueCount,
                        cacheCount: metrics.cacheCount,
                        checkpointCount: metrics.checkpointCount,
                        checkpointBytes: metrics.checkpointBytes,
                        rssBytes: try ProcessMemory.residentBytes()
                    )
                )
            }
        }

        return SoakRunReport(
            ticks: ticks,
            simulatedSeconds: simulatedSeconds,
            samples: samples,
            metricsStable: Self.metricsAreStable(samples),
            maximumPositiveSlopeBytesPerTenMinutes:
                Self.maximumPositiveSlope(samples: samples)
        )
    }

    private func advanceGenericTick(
        input: CombatInputFrame
    ) throws {
        try transaction.performTick { state, rng, queues in
            queues = AuthorityQueues(limits: configuration.limits)
            try queues.enqueueInput(input)
            try Self.advanceWorld(
                state: &state,
                rng: &rng,
                input: input,
                eventIncrement: 1
            )
        }
    }

    private func advanceQualifiedTick(
        input: CombatInputFrame
    ) throws {
        guard let qualifiedWorkload else {
            throw HeadlessFixtureError.unqualifiedBenchmarkFixture
        }

        let collisionBuild = try qualifiedWorkload.makeCollisionWorld(
            limits: configuration.limits
        )
        let collisionWorld = collisionBuild.world
        let candidatePairs = try collisionWorld.candidatePairs()
        let resolvedPairs = try collisionWorld.resolvedPairs(
            from: candidatePairs,
            iterationsPerPair: 1
        )
        var candidateChecksum: UInt64 = 0
        for pair in candidatePairs {
            candidateChecksum &+=
                UInt64(pair.minIndex) &* 31
                &+ UInt64(pair.maxIndex)
        }
        for pair in resolvedPairs {
            candidateChecksum ^=
                UInt64(pair.minIndex) << 32
                | UInt64(pair.maxIndex)
        }
        var sweptHits: [SweptCollisionHit] = []
        sweptHits.reserveCapacity(qualifiedWorkload.projectiles.count)
        for (offset, projectile) in
            qualifiedWorkload.projectiles.enumerated()
        {
            let blockerOffset =
                offset % qualifiedWorkload.blockers.count
            let target = qualifiedWorkload.blockers[blockerOffset]
            let path = QualifiedAuthorityWorkload.sweepPath(
                blockerOffset: blockerOffset
            )
            guard let hit = try collisionWorld.sweptSegment(
                from: path.start,
                to: path.end,
                radius: FixedPoint(rawValue: 0)
            ), hit.entity == target, hit.entity != projectile
            else {
                throw HeadlessFixtureError.unqualifiedBenchmarkFixture
            }
            sweptHits.append(hit)
            candidateChecksum ^=
                UInt64(hit.entity.index)
                &+ hit.fraction.numerator
                &+ hit.fraction.denominator
        }
        guard candidatePairs.count == 16_384,
              resolvedPairs.count == 4_096,
              sweptHits.count == 512
        else {
            throw HeadlessFixtureError.unqualifiedBenchmarkFixture
        }
        var acceptedInputs = 0
        var authorityEvents = 0
        var deferredCommands = 0
        try transaction.performTick { state, rng, queues in
            queues = AuthorityQueues(limits: configuration.limits)
            for offset in 0 ..< qualifiedWorkload.acceptedInputCount {
                try queues.enqueueInput(
                    try Self.input(
                        input,
                        sequence: input.sequence &+ UInt64(offset)
                    )
                )
            }
            acceptedInputs = queues.inputFrames.count

            var payloadValue = candidateChecksum.littleEndian
            let payload = withUnsafeBytes(of: &payloadValue) {
                Data($0)
            }
            for _ in 0 ..< qualifiedWorkload.authorityEventCount {
                try queues.enqueueEvent(payload)
            }
            authorityEvents = queues.events.count

            var commands = try DeferredCommandBuffer(
                limits: configuration.limits
            )
            for (
                sequence,
                entity
            ) in qualifiedWorkload.commandTargets.enumerated() {
                try commands.enqueue(
                    .setPosition(
                        entity,
                        FixedVector2(
                            x: FixedPoint(
                                rawValue: Int32(sequence % 1_024)
                            ),
                            y: FixedPoint(
                                rawValue: Int32(
                                    state.world.tick % 1_024
                                )
                            )
                        )
                    ),
                    key: CommandKey(
                        stage: 0,
                        systemOrder: 0,
                        sequence: UInt32(sequence)
                    )
                )
            }
            deferredCommands = commands.count
            _ = try commands.flush(into: &state.entities)

            try Self.advanceWorld(
                state: &state,
                rng: &rng,
                input: try Self.input(
                    input,
                    sequence: input.sequence &+ candidateChecksum
                ),
                eventIncrement: authorityEvents
            )
        }

        lastEvidence = QualifiedTickEvidence(
            candidatePairs: candidatePairs.count,
            resolvedPairs: resolvedPairs.count,
            sweptQueries: sweptHits.count,
            sweptHits: sweptHits.count,
            collisionWorldBuilds: 1,
            deferredCommands: deferredCommands,
            authorityEvents: authorityEvents,
            acceptedInputs: acceptedInputs
        )
        lastCollisionWorld = collisionWorld
    }

    private func qualifiedMetrics() throws -> QualifiedWorkloadMetrics {
        guard let qualifiedWorkload,
              let lastEvidence,
              let lastCollisionWorld
        else {
            throw HeadlessFixtureError.unqualifiedBenchmarkFixture
        }
        var componentCount = 0
        for kind in qualifiedWorkload.componentKinds
            + [DeferredCommandBuffer.positionComponentKind]
        {
            componentCount += try transaction.state.entities.stableQuery(
                requiring: [kind]
            ).entities.count
        }
        return QualifiedWorkloadMetrics(
            entityCount: transaction.state.entities.queryAll().count,
            componentCount: componentCount,
            occupiedBroadphaseCells:
                lastCollisionWorld.occupiedCellCount,
            candidatePairsPerTick: lastEvidence.candidatePairs,
            resolvedPairsPerTick: lastEvidence.resolvedPairs,
            sweptQueriesPerTick: lastEvidence.sweptQueries,
            sweptHitsPerTick: lastEvidence.sweptHits,
            collisionWorldBuildsPerTick:
                lastEvidence.collisionWorldBuilds,
            deferredCommandsPerTick: lastEvidence.deferredCommands,
            authorityEventsPerTick: transaction.queues.events.count,
            acceptedInputFramesPerTick:
                transaction.queues.inputFrames.count,
            queueCount:
                transaction.queues.events.count
                + transaction.queues.inputFrames.count
                + transaction.queues.outboundSnapshots.snapshots.count,
            cacheCount: Int(transaction.state.cacheVersion),
            checkpointCount: transaction.checkpointRing.entries.count,
            checkpointBytes: transaction.checkpointRing.totalBytes
        )
    }

    private func resolvedInput(
        _ input: CombatInputFrame,
        offset: Int
    ) throws -> CombatInputFrame {
        guard case .automatic = inputMode else {
            return input
        }
        let (sequence, overflow) = input.sequence.addingReportingOverflow(
            UInt64(offset)
        )
        guard !overflow else {
            throw HeadlessFixtureError.inputSequenceOverflow
        }
        return try Self.input(
            input,
            sequence: sequence,
            source: .automatic
        )
    }

    private static func input(
        _ input: CombatInputFrame,
        sequence: UInt64,
        source: CombatInputSource? = nil
    ) throws -> CombatInputFrame {
        try CombatInputFrame(
            contractVersion: input.contractVersion,
            targetTick: input.targetTick,
            controlledEntity: input.controlledEntity,
            sequence: sequence,
            source: source ?? input.source,
            move: input.move,
            aim: input.aim,
            buttons: input.buttons
        )
    }

    private static func advanceWorld(
        state: inout TickAuthorityState,
        rng: inout [RNGStreamID: DeterministicRNG],
        input: CombatInputFrame,
        eventIncrement: Int
    ) throws {
        let (nextTick, tickOverflow) =
            state.world.tick.addingReportingOverflow(1)
        guard !tickOverflow else {
            throw HeadlessFixtureError.tickOverflow
        }
        let (nextOrdinal, ordinalOverflow) =
            state.eventOrdinal.addingReportingOverflow(
                UInt64(eventIncrement)
            )
        guard !ordinalOverflow else {
            throw HeadlessFixtureError.eventOrdinalOverflow
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
        state.world.seed =
            simulationValue
            ^ combatValue
            ^ input.sequence
            ^ UInt64(input.buttons.rawValue)
    }

    private static func nanoseconds(_ duration: Duration) -> UInt64 {
        let components = duration.components
        guard components.seconds >= 0 else {
            return 0
        }
        let seconds = UInt64(components.seconds)
        let (secondNanoseconds, overflow) =
            seconds.multipliedReportingOverflow(by: 1_000_000_000)
        guard !overflow else {
            return .max
        }
        let subsecond = UInt64(max(0, components.attoseconds))
            / 1_000_000_000
        let (total, additionOverflow) =
            secondNanoseconds.addingReportingOverflow(subsecond)
        return additionOverflow ? .max : total
    }

    private static func metricsAreStable(
        _ samples: [SoakMetricSample]
    ) -> Bool {
        guard let first = samples.first else {
            return false
        }
        return samples.allSatisfy {
            $0.entityCount == first.entityCount
                && $0.componentCount == first.componentCount
                && $0.queueCount == first.queueCount
                && $0.cacheCount == first.cacheCount
                && $0.checkpointCount == first.checkpointCount
                && $0.checkpointBytes == first.checkpointBytes
        }
    }

    private static func maximumPositiveSlope(
        samples: [SoakMetricSample]
    ) -> Double {
        guard samples.count >= 2 else {
            return 0
        }
        let count = Double(samples.count)
        let meanX = samples.reduce(0.0) {
            $0 + (Double($1.tick) / 30)
        } / count
        let meanY = samples.reduce(0.0) {
            $0 + Double($1.rssBytes)
        } / count
        var numerator = 0.0
        var denominator = 0.0
        for sample in samples {
            let x = (Double(sample.tick) / 30) - meanX
            numerator += x * (Double(sample.rssBytes) - meanY)
            denominator += x * x
        }
        guard denominator > 0 else {
            return 0
        }
        return max(0, numerator / denominator) * 600
    }
}

struct HeadlessBenchmarkSample {
    let tickNanoseconds: [UInt64]
    let snapshot: CanonicalSnapshot
    let metrics: QualifiedWorkloadMetrics
    let peakRSSBytes: Int
}

struct QualifiedWorkloadMetrics: Hashable, Sendable {
    let entityCount: Int
    let componentCount: Int
    let occupiedBroadphaseCells: Int
    let candidatePairsPerTick: Int
    let resolvedPairsPerTick: Int
    let sweptQueriesPerTick: Int
    let sweptHitsPerTick: Int
    let collisionWorldBuildsPerTick: Int
    let deferredCommandsPerTick: Int
    let authorityEventsPerTick: Int
    let acceptedInputFramesPerTick: Int
    let queueCount: Int
    let cacheCount: Int
    let checkpointCount: Int
    let checkpointBytes: Int
}

private struct QualifiedTickEvidence {
    let candidatePairs: Int
    let resolvedPairs: Int
    let sweptQueries: Int
    let sweptHits: Int
    let collisionWorldBuilds: Int
    let deferredCommands: Int
    let authorityEvents: Int
    let acceptedInputs: Int
}

private struct QualifiedAuthorityConstruction {
    let entities: EntityStore
    let workload: QualifiedAuthorityWorkload
}

private struct QualifiedCollisionBuild {
    let world: CollisionWorld
    let circleCenters: [FixedVector2]
}

private struct QualifiedAuthorityWorkload {
    static let movingKind = ComponentKind(rawValue: 10)
    static let blockerKind = ComponentKind(rawValue: 11)
    static let projectileKind = ComponentKind(rawValue: 12)
    static let stateOnlyKind = ComponentKind(rawValue: 13)

    let circles: [EntityHandle]
    let blockers: [EntityHandle]
    let projectiles: [EntityHandle]
    let componentKinds: [ComponentKind]
    let authorityEventCount: Int
    let acceptedInputCount: Int

    var commandTargets: [EntityHandle] {
        circles
    }

    static func make(
        manifest: BenchmarkFixtureManifest,
        limits: RealtimeLimits
    ) throws -> QualifiedAuthorityConstruction {
        try manifest.validateQualifiedV1()
        var entities = try EntityStore(limits: limits)
        let componentKinds = [
            movingKind,
            blockerKind,
            projectileKind,
            stateOnlyKind,
        ]
        for kind in componentKinds {
            try entities.registerComponentKind(kind)
        }

        let moving = try spawn(
            count: manifest.movingCircles,
            kind: movingKind,
            in: &entities
        )
        let blockers = try spawn(
            count: manifest.staticAABBBlockers,
            kind: blockerKind,
            in: &entities
        )
        let projectiles = try spawn(
            count: manifest.sweptProjectiles,
            kind: projectileKind,
            in: &entities
        )
        _ = try spawn(
            count: manifest.stateOnlyEntities,
            kind: stateOnlyKind,
            in: &entities
        )

        let circles = moving + projectiles
        let workload = QualifiedAuthorityWorkload(
            circles: circles,
            blockers: blockers,
            projectiles: projectiles,
            componentKinds: componentKinds,
            authorityEventCount: manifest.authorityEventsPerTick,
            acceptedInputCount: manifest.acceptedInputFramesPerTick
        )
        let collisionBuild = try workload.makeCollisionWorld(
            limits: limits
        )
        let candidatePairs = try collisionBuild.world.candidatePairs()
        let resolvedPairs = try collisionBuild.world.resolvedPairs(
            iterationsPerPair: 1
        )
        guard collisionBuild.world.bodyCount
                == manifest.movingCircles
                + manifest.staticAABBBlockers
                + manifest.sweptProjectiles,
              collisionBuild.world.occupiedCellCount
                == manifest.occupiedBroadphaseCells,
              candidatePairs.count == manifest.candidatePairsPerTick,
              resolvedPairs.count == manifest.resolvedPairsPerTick,
              circles.count == manifest.deferredCommandsPerTick
        else {
            throw HeadlessFixtureError.unqualifiedBenchmarkFixture
        }

        return QualifiedAuthorityConstruction(
            entities: entities,
            workload: workload
        )
    }

    func makeCollisionWorld(
        limits: RealtimeLimits
    ) throws -> QualifiedCollisionBuild {
        var collisionWorld = try CollisionWorld(limits: limits)
        let entityCount =
            circles.count + blockers.count + 320
        var circleCenters = Array(
            repeating: FixedVector2(
                x: FixedPoint(rawValue: 0),
                y: FixedPoint(rawValue: 0)
            ),
            count: entityCount
        )
        var circleOffset = 0

        try Self.insertCluster(
            Array(circles[circleOffset ..< circleOffset + 181]),
            cellX: 0,
            centers: &circleCenters,
            world: &collisionWorld
        )
        circleOffset += 181
        try Self.insertUniqueCluster(
            Array(circles[circleOffset ..< circleOffset + 14]),
            cellX: 1,
            centers: &circleCenters,
            world: &collisionWorld
        )
        circleOffset += 14
        try Self.insertUniqueCluster(
            Array(circles[circleOffset ..< circleOffset + 3]),
            cellX: 2,
            centers: &circleCenters,
            world: &collisionWorld
        )
        circleOffset += 3

        for (offset, entity) in circles[circleOffset...].enumerated() {
            let center = Self.cellCenter(x: 100 + offset, y: 10)
            circleCenters[Int(entity.index)] = center
            try collisionWorld.insertCircle(
                entity: entity,
                center: center,
                radius: FixedPoint(rawValue: 0)
            )
        }

        for (offset, entity) in blockers.enumerated() {
            if offset < 195 {
                try Self.insertStrip(
                    entity: entity,
                    baseCellX: 1_000 + (offset * 6),
                    cellY: 20,
                    cellWidth: 5,
                    world: &collisionWorld
                )
            } else {
                try Self.insertStrip(
                    entity: entity,
                    baseCellX: 3_000 + ((offset - 195) * 5),
                    cellY: 30,
                    cellWidth: 4,
                    world: &collisionWorld
                )
            }
        }

        return QualifiedCollisionBuild(
            world: collisionWorld,
            circleCenters: circleCenters
        )
    }

    static func sweepPath(
        blockerOffset: Int
    ) -> (start: FixedVector2, end: FixedVector2) {
        let baseCellX: Int
        let cellY: Int
        let centerX: Int32
        let halfExtentX: Int32
        if blockerOffset < 195 {
            baseCellX = 1_000 + (blockerOffset * 6)
            cellY = 20
            centerX = Int32(
                (baseCellX + 2) * Int(FixedPoint.scale) + 512
            )
            halfExtentX = 2_047
        } else {
            baseCellX = 3_000 + ((blockerOffset - 195) * 5)
            cellY = 30
            centerX = Int32(
                (baseCellX + 2) * Int(FixedPoint.scale)
            )
            halfExtentX = 1_535
        }
        let y = FixedPoint(
            rawValue: Int32(cellY * Int(FixedPoint.scale) + 512)
        )
        return (
            start: FixedVector2(
                x: FixedPoint(
                    rawValue: centerX - halfExtentX - 1
                ),
                y: y
            ),
            end: FixedVector2(
                x: FixedPoint(
                    rawValue: centerX - halfExtentX + 1
                ),
                y: y
            )
        )
    }

    private static func spawn(
        count: Int,
        kind: ComponentKind,
        in entities: inout EntityStore
    ) throws -> [EntityHandle] {
        var result: [EntityHandle] = []
        result.reserveCapacity(count)
        for index in 0 ..< count {
            let entity = try entities.spawn()
            _ = try entities.attachComponent(
                .unsigned(UInt32(index)),
                kind: kind,
                to: entity
            )
            result.append(entity)
        }
        return result
    }

    private static func insertCluster(
        _ entities: [EntityHandle],
        cellX: Int,
        centers: inout [FixedVector2],
        world: inout CollisionWorld
    ) throws {
        for (offset, entity) in entities.enumerated() {
            let center: FixedVector2
            if offset < 91 {
                center = point(inCellX: cellX, rawX: 100, rawY: 100)
            } else if offset < 93 {
                center = point(inCellX: cellX, rawX: 200, rawY: 200)
            } else {
                center = point(
                    inCellX: cellX,
                    rawX: 300 + (offset - 93),
                    rawY: 300
                )
            }
            centers[Int(entity.index)] = center
            try world.insertCircle(
                entity: entity,
                center: center,
                radius: FixedPoint(rawValue: 0)
            )
        }
    }

    private static func insertUniqueCluster(
        _ entities: [EntityHandle],
        cellX: Int,
        centers: inout [FixedVector2],
        world: inout CollisionWorld
    ) throws {
        for (offset, entity) in entities.enumerated() {
            let center = point(
                inCellX: cellX,
                rawX: 100 + offset,
                rawY: 100
            )
            centers[Int(entity.index)] = center
            try world.insertCircle(
                entity: entity,
                center: center,
                radius: FixedPoint(rawValue: 0)
            )
        }
    }

    private static func insertStrip(
        entity: EntityHandle,
        baseCellX: Int,
        cellY: Int,
        cellWidth: Int,
        world: inout CollisionWorld
    ) throws {
        let centerX: Int32
        let halfExtentX: Int32
        switch cellWidth {
        case 5:
            centerX = Int32(
                (baseCellX + 2) * Int(FixedPoint.scale) + 512
            )
            halfExtentX = 2_047
        case 4:
            centerX = Int32(
                (baseCellX + 2) * Int(FixedPoint.scale)
            )
            halfExtentX = 1_535
        default:
            throw HeadlessFixtureError.unqualifiedBenchmarkFixture
        }
        try world.insertAABB(
            entity: entity,
            center: FixedVector2(
                x: FixedPoint(rawValue: centerX),
                y: FixedPoint(
                    rawValue: Int32(
                        cellY * Int(FixedPoint.scale) + 512
                    )
                )
            ),
            halfExtents: FixedVector2(
                x: FixedPoint(rawValue: halfExtentX),
                y: FixedPoint(rawValue: 0)
            )
        )
    }

    private static func point(
        inCellX cellX: Int,
        rawX: Int,
        rawY: Int
    ) -> FixedVector2 {
        FixedVector2(
            x: FixedPoint(
                rawValue: Int32(
                    cellX * Int(FixedPoint.scale) + rawX
                )
            ),
            y: FixedPoint(rawValue: Int32(rawY))
        )
    }

    private static func cellCenter(
        x: Int,
        y: Int
    ) -> FixedVector2 {
        FixedVector2(
            x: FixedPoint(
                rawValue: Int32(
                    x * Int(FixedPoint.scale) + 512
                )
            ),
            y: FixedPoint(
                rawValue: Int32(
                    y * Int(FixedPoint.scale) + 512
                )
            )
        )
    }
}

enum ProcessMemory {
    static func residentBytes() throws -> Int {
        var info = mach_task_basic_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info_data_t>.size
                / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(
                to: integer_t.self,
                capacity: Int(count)
            ) {
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    $0,
                    &count
                )
            }
        }
        guard result == KERN_SUCCESS else {
            throw HeadlessFixtureError.memoryMeasurementFailed(result)
        }
        return Int(info.resident_size)
    }
}
