#if canImport(CryptoKit)
import CryptoKit
import Foundation
import GameRealtimeEngineKit
import GameRealtimeProtocolKit
import GameRealtimeStateKit

@_spi(GameRealtimeBenchmark)
public struct BenchmarkFixtureManifest:
    Hashable,
    Codable,
    Sendable
{
    public let schema: String
    public let fixtureID: String
    public let movingCircles: Int
    public let staticAABBBlockers: Int
    public let sweptProjectiles: Int
    public let stateOnlyEntities: Int
    public let occupiedBroadphaseCells: Int
    public let candidatePairsPerTick: Int
    public let resolvedPairsPerTick: Int
    public let deferredCommandsPerTick: Int
    public let authorityEventsPerTick: Int
    public let acceptedInputFramesPerTick: Int

    var entityCount: Int {
        movingCircles
            + staticAABBBlockers
            + sweptProjectiles
            + stateOnlyEntities
    }

    func validateQualifiedV1() throws {
        guard schema == "game-realtime-benchmark-fixture-v1",
              fixtureID == "p0-core-1600-v1",
              movingCircles == 512,
              staticAABBBlockers == 256,
              sweptProjectiles == 512,
              stateOnlyEntities == 320,
              entityCount == 1_600,
              occupiedBroadphaseCells == 2_048,
              candidatePairsPerTick == 16_384,
              resolvedPairsPerTick == 4_096,
              deferredCommandsPerTick == 1_024,
              authorityEventsPerTick == 1_024,
              acceptedInputFramesPerTick == 128
        else {
            throw BenchmarkError.unqualifiedFixture
        }
    }
}

@_spi(GameRealtimeBenchmark)
public struct BenchmarkBaseline: Hashable, Codable, Sendable {
    public let schema: String
    public let hostProfileID: String
    public let fixtureID: String
    public let medianP99Nanoseconds: UInt64
    public let peakRSSDeltaBytes: Int
    public let snapshotBytes: Int
    public let checkpointRingBytes: Int

    public static let requiredSHA256 =
        "dc94ecdc345656caa339715eae8b5762b2550b278a07870934ed53a6f56ebf8d"

    public static func decodeQualified(
        _ data: Data
    ) throws -> BenchmarkBaseline {
        let digest = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
        guard digest == requiredSHA256 else {
            throw BenchmarkError.baselineHashMismatch(
                expected: requiredSHA256,
                actual: digest
            )
        }
        let baseline = try JSONDecoder().decode(
            BenchmarkBaseline.self,
            from: data
        )
        guard baseline.schema
                == "game-realtime-benchmark-baseline-v1"
        else {
            throw BenchmarkError.unqualifiedBaseline
        }
        return baseline
    }
}

public struct BenchmarkReport: Hashable, Codable, Sendable {
    public struct Identity: Hashable, Sendable {
        public var schema: String
        public var hostProfileID: String
        public var fixtureID: String
        public var toolchain: String
        public var operatingSystem: String

        public init(
            schema: String,
            hostProfileID: String,
            fixtureID: String,
            toolchain: String,
            operatingSystem: String
        ) {
            self.schema = schema
            self.hostProfileID = hostProfileID
            self.fixtureID = fixtureID
            self.toolchain = toolchain
            self.operatingSystem = operatingSystem
        }
    }

    public struct Timing: Hashable, Sendable {
        public var warmUpTicks: Int
        public var ticksPerSample: Int
        public var p99Nanoseconds: [UInt64]
        public var medianP99Nanoseconds: UInt64
        public var maximumP99Nanoseconds: UInt64
        public var sampleStartTicks: [UInt64]

        public init(
            warmUpTicks: Int,
            ticksPerSample: Int,
            p99Nanoseconds: [UInt64],
            medianP99Nanoseconds: UInt64,
            maximumP99Nanoseconds: UInt64,
            sampleStartTicks: [UInt64]
        ) {
            self.warmUpTicks = warmUpTicks
            self.ticksPerSample = ticksPerSample
            self.p99Nanoseconds = p99Nanoseconds
            self.medianP99Nanoseconds = medianP99Nanoseconds
            self.maximumP99Nanoseconds = maximumP99Nanoseconds
            self.sampleStartTicks = sampleStartTicks
        }
    }

    public struct Memory: Hashable, Sendable {
        public var peakRSSBytes: Int
        public var peakRSSDeltaBytes: Int
        public var snapshotBytes: Int
        public var checkpointRingCount: Int
        public var checkpointRingBytes: Int

        public init(
            peakRSSBytes: Int,
            peakRSSDeltaBytes: Int,
            snapshotBytes: Int,
            checkpointRingCount: Int,
            checkpointRingBytes: Int
        ) {
            self.peakRSSBytes = peakRSSBytes
            self.peakRSSDeltaBytes = peakRSSDeltaBytes
            self.snapshotBytes = snapshotBytes
            self.checkpointRingCount = checkpointRingCount
            self.checkpointRingBytes = checkpointRingBytes
        }
    }

    public struct Population: Hashable, Sendable {
        public var entityCount: Int
        public var componentCount: Int
        public var occupiedBroadphaseCells: Int
        public var candidatePairsPerTick: Int
        public var resolvedPairsPerTick: Int

        public init(
            entityCount: Int,
            componentCount: Int,
            occupiedBroadphaseCells: Int,
            candidatePairsPerTick: Int,
            resolvedPairsPerTick: Int
        ) {
            self.entityCount = entityCount
            self.componentCount = componentCount
            self.occupiedBroadphaseCells = occupiedBroadphaseCells
            self.candidatePairsPerTick = candidatePairsPerTick
            self.resolvedPairsPerTick = resolvedPairsPerTick
        }
    }

    public struct TickLoad: Hashable, Sendable {
        public var sweptQueriesPerTick: Int
        public var collisionWorldBuildsPerTick: Int
        public var deferredCommandsPerTick: Int
        public var authorityEventsPerTick: Int
        public var acceptedInputFramesPerTick: Int

        public init(
            sweptQueriesPerTick: Int,
            collisionWorldBuildsPerTick: Int,
            deferredCommandsPerTick: Int,
            authorityEventsPerTick: Int,
            acceptedInputFramesPerTick: Int
        ) {
            self.sweptQueriesPerTick = sweptQueriesPerTick
            self.collisionWorldBuildsPerTick = collisionWorldBuildsPerTick
            self.deferredCommandsPerTick = deferredCommandsPerTick
            self.authorityEventsPerTick = authorityEventsPerTick
            self.acceptedInputFramesPerTick = acceptedInputFramesPerTick
        }
    }

    public struct Soak: Hashable, Sendable {
        public var soakTicks: Int
        public var soakSimulatedSeconds: Int
        public var soakSampleCount: Int
        public var soakMetricsStable: Bool
        public var soakMaximumPositiveSlopeBytesPerTenMinutes: Double
        public var qualified: Bool

        public init(
            soakTicks: Int,
            soakSimulatedSeconds: Int,
            soakSampleCount: Int,
            soakMetricsStable: Bool,
            soakMaximumPositiveSlopeBytesPerTenMinutes: Double,
            qualified: Bool
        ) {
            self.soakTicks = soakTicks
            self.soakSimulatedSeconds = soakSimulatedSeconds
            self.soakSampleCount = soakSampleCount
            self.soakMetricsStable = soakMetricsStable
            self.soakMaximumPositiveSlopeBytesPerTenMinutes =
                soakMaximumPositiveSlopeBytesPerTenMinutes
            self.qualified = qualified
        }
    }

    public let identity: Identity
    public let timing: Timing
    public let memory: Memory
    public let population: Population
    public let tickLoad: TickLoad
    public let soak: Soak

    public var schema: String { identity.schema }
    public var hostProfileID: String { identity.hostProfileID }
    public var fixtureID: String { identity.fixtureID }
    public var toolchain: String { identity.toolchain }
    public var operatingSystem: String { identity.operatingSystem }
    public var warmUpTicks: Int { timing.warmUpTicks }
    public var ticksPerSample: Int { timing.ticksPerSample }
    public var p99Nanoseconds: [UInt64] { timing.p99Nanoseconds }
    public var medianP99Nanoseconds: UInt64 { timing.medianP99Nanoseconds }
    public var maximumP99Nanoseconds: UInt64 { timing.maximumP99Nanoseconds }
    public var sampleStartTicks: [UInt64] { timing.sampleStartTicks }
    public var peakRSSBytes: Int { memory.peakRSSBytes }
    public var peakRSSDeltaBytes: Int { memory.peakRSSDeltaBytes }
    public var snapshotBytes: Int { memory.snapshotBytes }
    public var checkpointRingCount: Int { memory.checkpointRingCount }
    public var checkpointRingBytes: Int { memory.checkpointRingBytes }
    public var entityCount: Int { population.entityCount }
    public var componentCount: Int { population.componentCount }
    public var occupiedBroadphaseCells: Int { population.occupiedBroadphaseCells }
    public var candidatePairsPerTick: Int { population.candidatePairsPerTick }
    public var resolvedPairsPerTick: Int { population.resolvedPairsPerTick }
    public var sweptQueriesPerTick: Int { tickLoad.sweptQueriesPerTick }
    public var collisionWorldBuildsPerTick: Int { tickLoad.collisionWorldBuildsPerTick }
    public var deferredCommandsPerTick: Int { tickLoad.deferredCommandsPerTick }
    public var authorityEventsPerTick: Int { tickLoad.authorityEventsPerTick }
    public var acceptedInputFramesPerTick: Int { tickLoad.acceptedInputFramesPerTick }
    public var soakTicks: Int { soak.soakTicks }
    public var soakSimulatedSeconds: Int { soak.soakSimulatedSeconds }
    public var soakSampleCount: Int { soak.soakSampleCount }
    public var soakMetricsStable: Bool { soak.soakMetricsStable }
    public var soakMaximumPositiveSlopeBytesPerTenMinutes: Double {
        soak.soakMaximumPositiveSlopeBytesPerTenMinutes
    }
    public var qualified: Bool { soak.qualified }

    public init(
        identity: Identity,
        timing: Timing,
        memory: Memory,
        population: Population,
        tickLoad: TickLoad,
        soak: Soak
    ) {
        self.identity = identity
        self.timing = timing
        self.memory = memory
        self.population = population
        self.tickLoad = tickLoad
        self.soak = soak
    }

    private enum CodingKeys: String, CodingKey {
        case schema
        case hostProfileID
        case fixtureID
        case toolchain
        case operatingSystem
        case warmUpTicks
        case ticksPerSample
        case p99Nanoseconds
        case medianP99Nanoseconds
        case maximumP99Nanoseconds
        case sampleStartTicks
        case peakRSSBytes
        case peakRSSDeltaBytes
        case snapshotBytes
        case checkpointRingCount
        case checkpointRingBytes
        case entityCount
        case componentCount
        case occupiedBroadphaseCells
        case candidatePairsPerTick
        case resolvedPairsPerTick
        case sweptQueriesPerTick
        case collisionWorldBuildsPerTick
        case deferredCommandsPerTick
        case authorityEventsPerTick
        case acceptedInputFramesPerTick
        case soakTicks
        case soakSimulatedSeconds
        case soakSampleCount
        case soakMetricsStable
        case soakMaximumPositiveSlopeBytesPerTenMinutes
        case qualified
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        identity = Identity(
            schema: try container.decode(String.self, forKey: .schema),
            hostProfileID: try container.decode(String.self, forKey: .hostProfileID),
            fixtureID: try container.decode(String.self, forKey: .fixtureID),
            toolchain: try container.decode(String.self, forKey: .toolchain),
            operatingSystem: try container.decode(String.self, forKey: .operatingSystem)
        )
        timing = Timing(
            warmUpTicks: try container.decode(Int.self, forKey: .warmUpTicks),
            ticksPerSample: try container.decode(Int.self, forKey: .ticksPerSample),
            p99Nanoseconds: try container.decode([UInt64].self, forKey: .p99Nanoseconds),
            medianP99Nanoseconds: try container.decode(
                UInt64.self,
                forKey: .medianP99Nanoseconds
            ),
            maximumP99Nanoseconds: try container.decode(
                UInt64.self,
                forKey: .maximumP99Nanoseconds
            ),
            sampleStartTicks: try container.decode(
                [UInt64].self,
                forKey: .sampleStartTicks
            )
        )
        memory = Memory(
            peakRSSBytes: try container.decode(Int.self, forKey: .peakRSSBytes),
            peakRSSDeltaBytes: try container.decode(Int.self, forKey: .peakRSSDeltaBytes),
            snapshotBytes: try container.decode(Int.self, forKey: .snapshotBytes),
            checkpointRingCount: try container.decode(
                Int.self,
                forKey: .checkpointRingCount
            ),
            checkpointRingBytes: try container.decode(
                Int.self,
                forKey: .checkpointRingBytes
            )
        )
        population = Population(
            entityCount: try container.decode(Int.self, forKey: .entityCount),
            componentCount: try container.decode(Int.self, forKey: .componentCount),
            occupiedBroadphaseCells: try container.decode(
                Int.self,
                forKey: .occupiedBroadphaseCells
            ),
            candidatePairsPerTick: try container.decode(
                Int.self,
                forKey: .candidatePairsPerTick
            ),
            resolvedPairsPerTick: try container.decode(
                Int.self,
                forKey: .resolvedPairsPerTick
            )
        )
        tickLoad = TickLoad(
            sweptQueriesPerTick: try container.decode(
                Int.self,
                forKey: .sweptQueriesPerTick
            ),
            collisionWorldBuildsPerTick: try container.decode(
                Int.self,
                forKey: .collisionWorldBuildsPerTick
            ),
            deferredCommandsPerTick: try container.decode(
                Int.self,
                forKey: .deferredCommandsPerTick
            ),
            authorityEventsPerTick: try container.decode(
                Int.self,
                forKey: .authorityEventsPerTick
            ),
            acceptedInputFramesPerTick: try container.decode(
                Int.self,
                forKey: .acceptedInputFramesPerTick
            )
        )
        soak = Soak(
            soakTicks: try container.decode(Int.self, forKey: .soakTicks),
            soakSimulatedSeconds: try container.decode(
                Int.self,
                forKey: .soakSimulatedSeconds
            ),
            soakSampleCount: try container.decode(Int.self, forKey: .soakSampleCount),
            soakMetricsStable: try container.decode(Bool.self, forKey: .soakMetricsStable),
            soakMaximumPositiveSlopeBytesPerTenMinutes: try container.decode(
                Double.self,
                forKey: .soakMaximumPositiveSlopeBytesPerTenMinutes
            ),
            qualified: try container.decode(Bool.self, forKey: .qualified)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schema, forKey: .schema)
        try container.encode(hostProfileID, forKey: .hostProfileID)
        try container.encode(fixtureID, forKey: .fixtureID)
        try container.encode(toolchain, forKey: .toolchain)
        try container.encode(operatingSystem, forKey: .operatingSystem)
        try container.encode(warmUpTicks, forKey: .warmUpTicks)
        try container.encode(ticksPerSample, forKey: .ticksPerSample)
        try container.encode(p99Nanoseconds, forKey: .p99Nanoseconds)
        try container.encode(medianP99Nanoseconds, forKey: .medianP99Nanoseconds)
        try container.encode(maximumP99Nanoseconds, forKey: .maximumP99Nanoseconds)
        try container.encode(sampleStartTicks, forKey: .sampleStartTicks)
        try container.encode(peakRSSBytes, forKey: .peakRSSBytes)
        try container.encode(peakRSSDeltaBytes, forKey: .peakRSSDeltaBytes)
        try container.encode(snapshotBytes, forKey: .snapshotBytes)
        try container.encode(checkpointRingCount, forKey: .checkpointRingCount)
        try container.encode(checkpointRingBytes, forKey: .checkpointRingBytes)
        try container.encode(entityCount, forKey: .entityCount)
        try container.encode(componentCount, forKey: .componentCount)
        try container.encode(occupiedBroadphaseCells, forKey: .occupiedBroadphaseCells)
        try container.encode(candidatePairsPerTick, forKey: .candidatePairsPerTick)
        try container.encode(resolvedPairsPerTick, forKey: .resolvedPairsPerTick)
        try container.encode(sweptQueriesPerTick, forKey: .sweptQueriesPerTick)
        try container.encode(
            collisionWorldBuildsPerTick,
            forKey: .collisionWorldBuildsPerTick
        )
        try container.encode(deferredCommandsPerTick, forKey: .deferredCommandsPerTick)
        try container.encode(authorityEventsPerTick, forKey: .authorityEventsPerTick)
        try container.encode(
            acceptedInputFramesPerTick,
            forKey: .acceptedInputFramesPerTick
        )
        try container.encode(soakTicks, forKey: .soakTicks)
        try container.encode(soakSimulatedSeconds, forKey: .soakSimulatedSeconds)
        try container.encode(soakSampleCount, forKey: .soakSampleCount)
        try container.encode(soakMetricsStable, forKey: .soakMetricsStable)
        try container.encode(
            soakMaximumPositiveSlopeBytesPerTenMinutes,
            forKey: .soakMaximumPositiveSlopeBytesPerTenMinutes
        )
        try container.encode(qualified, forKey: .qualified)
    }
}

@_spi(GameRealtimeBenchmark)
public enum BenchmarkError: Error, Equatable, Sendable {
    case unqualifiedFixture
    case unqualifiedBaseline
    case baselineHashMismatch(expected: String, actual: String)
    case hostProfileMismatch(expected: String, actual: String)
    case fixtureIDMismatch(expected: String, actual: String)
    case sampleCount(Int)
    case emptySample
    case inconsistentWorkload
    case thresholdFailure
}

@_spi(GameRealtimeBenchmark)
public struct BenchmarkHarness: Sendable {
    public static let warmUpTicks = 1_000
    public static let ticksPerSample = 10_000
    public static let soakTicks = 18_000
    public static let soakSeconds = 600

    public let hostProfileID: String
    public let fixtureManifest: BenchmarkFixtureManifest
    public let baseline: BenchmarkBaseline
    public let samples: Int

    public init(
        hostProfileID: String,
        fixtureManifest: BenchmarkFixtureManifest,
        baseline: BenchmarkBaseline,
        samples: Int
    ) throws {
        try fixtureManifest.validateQualifiedV1()
        guard baseline.hostProfileID == hostProfileID else {
            throw BenchmarkError.hostProfileMismatch(
                expected: baseline.hostProfileID,
                actual: hostProfileID
            )
        }
        guard baseline.fixtureID == fixtureManifest.fixtureID else {
            throw BenchmarkError.fixtureIDMismatch(
                expected: baseline.fixtureID,
                actual: fixtureManifest.fixtureID
            )
        }
        guard samples == 5 else {
            throw BenchmarkError.sampleCount(samples)
        }
        self.hostProfileID = hostProfileID
        self.fixtureManifest = fixtureManifest
        self.baseline = baseline
        self.samples = samples
    }

    public func run() throws -> BenchmarkReport {
        let configuration = try GameRealtimeConfiguration()
        let input = try Self.inputFrame(sequence: 1)
        let initialRSSBytes = try ProcessMemory.residentBytes()
        var peakRSSBytes = initialRSSBytes
        var p99Values: [UInt64] = []
        var sampleStartTicks: [UInt64] = []
        var maximumSnapshotBytes = 0
        var maximumCheckpointCount = 0
        var maximumCheckpointBytes = 0
        var measuredWorkload: QualifiedWorkloadMetrics?
        p99Values.reserveCapacity(samples)
        sampleStartTicks.reserveCapacity(samples)

        for _ in 0 ..< samples {
            let fixture = try HeadlessFixture(
                configuration: configuration,
                inputMode: .manual,
                qualified: fixtureManifest
            )
            let warmUp = try fixture.benchmarkSample(
                ticks: Self.warmUpTicks,
                input: input,
                measureDurations: false
            )
            sampleStartTicks.append(warmUp.snapshot.tick)

            let measured = try fixture.benchmarkSample(
                ticks: Self.ticksPerSample,
                input: input,
                measureDurations: true
            )
            p99Values.append(
                try Self.nearestRankP99(measured.tickNanoseconds)
            )
            peakRSSBytes = max(peakRSSBytes, measured.peakRSSBytes)
            maximumSnapshotBytes = max(
                maximumSnapshotBytes,
                measured.snapshot.canonicalBytes.count
            )
            maximumCheckpointBytes = max(
                maximumCheckpointBytes,
                measured.metrics.checkpointBytes
            )
            maximumCheckpointCount = max(
                maximumCheckpointCount,
                measured.metrics.checkpointCount
            )
            if let measuredWorkload,
               measuredWorkload != measured.metrics
            {
                throw BenchmarkError.inconsistentWorkload
            }
            measuredWorkload = measured.metrics
        }

        guard let measuredWorkload,
              let maximumP99 = p99Values.max()
        else {
            throw BenchmarkError.emptySample
        }
        let medianP99 = p99Values.sorted()[samples / 2]

        let soakFixture = try HeadlessFixture(
            configuration: configuration,
            inputMode: .manual,
            qualified: fixtureManifest
        )
        let soak = try soakFixture.soak(
            ticks: Self.soakTicks,
            simulatedSeconds: Self.soakSeconds,
            input: input
        )
        if let soakPeak = soak.samples.map(\.rssBytes).max() {
            peakRSSBytes = max(peakRSSBytes, soakPeak)
        }
        if let soakCheckpoint = soak.samples.map(\.checkpointBytes).max() {
            maximumCheckpointBytes = max(
                maximumCheckpointBytes,
                soakCheckpoint
            )
        }
        if let soakCheckpointCount =
            soak.samples.map(\.checkpointCount).max()
        {
            maximumCheckpointCount = max(
                maximumCheckpointCount,
                soakCheckpointCount
            )
        }

        let peakRSSDeltaBytes = max(0, peakRSSBytes - initialRSSBytes)
        let regressionP99Limit =
            baseline.medianP99Nanoseconds
                + (baseline.medianP99Nanoseconds / 10)
        let workloadMatchesManifest =
            measuredWorkload.entityCount == fixtureManifest.entityCount
            && measuredWorkload.componentCount == 2_624
            && measuredWorkload.occupiedBroadphaseCells
                == fixtureManifest.occupiedBroadphaseCells
            && measuredWorkload.candidatePairsPerTick
                == fixtureManifest.candidatePairsPerTick
            && measuredWorkload.resolvedPairsPerTick
                == fixtureManifest.resolvedPairsPerTick
            && measuredWorkload.sweptQueriesPerTick
                == fixtureManifest.sweptProjectiles
            && measuredWorkload.collisionWorldBuildsPerTick == 1
            && measuredWorkload.deferredCommandsPerTick
                == fixtureManifest.deferredCommandsPerTick
            && measuredWorkload.authorityEventsPerTick
                == fixtureManifest.authorityEventsPerTick
            && measuredWorkload.acceptedInputFramesPerTick
                == fixtureManifest.acceptedInputFramesPerTick
        let qualified =
            workloadMatchesManifest
            && sampleStartTicks.allSatisfy {
                $0 == UInt64(Self.warmUpTicks)
            }
            && medianP99 <= regressionP99Limit
            && maximumP99 <= 8_000_000
            && peakRSSDeltaBytes <= baseline.peakRSSDeltaBytes
            && peakRSSBytes <= 134_217_728
            && maximumSnapshotBytes <= baseline.snapshotBytes
            && maximumCheckpointCount > 1
            && maximumCheckpointCount
                <= configuration.limits.checkpointRingLength
            && maximumCheckpointBytes <= baseline.checkpointRingBytes
            && soak.ticks == Self.soakTicks
            && soak.simulatedSeconds == Self.soakSeconds
            && soak.samples.count == 30
            && soak.metricsStable
            && soak.maximumPositiveSlopeBytesPerTenMinutes
                <= 1_048_576
        guard qualified else {
            throw BenchmarkError.thresholdFailure
        }

        return BenchmarkReport(
            identity: .init(
                schema: "game-realtime-benchmark-report-v1",
                hostProfileID: hostProfileID,
                fixtureID: fixtureManifest.fixtureID,
                toolchain: "swift-6-release",
                operatingSystem: ProcessInfo.processInfo
                    .operatingSystemVersionString
            ),
            timing: .init(
                warmUpTicks: Self.warmUpTicks,
                ticksPerSample: Self.ticksPerSample,
                p99Nanoseconds: p99Values,
                medianP99Nanoseconds: medianP99,
                maximumP99Nanoseconds: maximumP99,
                sampleStartTicks: sampleStartTicks
            ),
            memory: .init(
                peakRSSBytes: peakRSSBytes,
                peakRSSDeltaBytes: peakRSSDeltaBytes,
                snapshotBytes: maximumSnapshotBytes,
                checkpointRingCount: maximumCheckpointCount,
                checkpointRingBytes: maximumCheckpointBytes
            ),
            population: .init(
                entityCount: measuredWorkload.entityCount,
                componentCount: measuredWorkload.componentCount,
                occupiedBroadphaseCells:
                    measuredWorkload.occupiedBroadphaseCells,
                candidatePairsPerTick:
                    measuredWorkload.candidatePairsPerTick,
                resolvedPairsPerTick:
                    measuredWorkload.resolvedPairsPerTick
            ),
            tickLoad: .init(
                sweptQueriesPerTick:
                    measuredWorkload.sweptQueriesPerTick,
                collisionWorldBuildsPerTick:
                    measuredWorkload.collisionWorldBuildsPerTick,
                deferredCommandsPerTick:
                    measuredWorkload.deferredCommandsPerTick,
                authorityEventsPerTick:
                    measuredWorkload.authorityEventsPerTick,
                acceptedInputFramesPerTick:
                    measuredWorkload.acceptedInputFramesPerTick
            ),
            soak: .init(
                soakTicks: soak.ticks,
                soakSimulatedSeconds: soak.simulatedSeconds,
                soakSampleCount: soak.samples.count,
                soakMetricsStable: soak.metricsStable,
                soakMaximumPositiveSlopeBytesPerTenMinutes:
                    soak.maximumPositiveSlopeBytesPerTenMinutes,
                qualified: true
            )
        )
    }

    static func nearestRankP99(
        _ values: [UInt64]
    ) throws -> UInt64 {
        guard !values.isEmpty else {
            throw BenchmarkError.emptySample
        }
        let sorted = values.sorted()
        let rank = ((99 * sorted.count) + 99) / 100
        return sorted[rank - 1]
    }

    private static func inputFrame(
        sequence: UInt64
    ) throws -> CombatInputFrame {
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
                x: FixedPoint(rawValue: FixedPoint.scale),
                y: FixedPoint(rawValue: 0)
            ),
            buttons: [.primaryAction]
        )
    }
}
#endif
