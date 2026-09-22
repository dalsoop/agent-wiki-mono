import Foundation
@_spi(GameRealtimeBenchmark) @testable import GameRealtimeDebugKit
@testable import GameRealtimeEngineKit
import GameRealtimeProtocolKit
import GameRealtimeRuntimeKit
import GameRealtimeStateKit
import XCTest

final class HeadlessAcceptanceTests: XCTestCase {
    func testDeterminismLifecycleAndLimits() async throws {
        let input = try loadInputFixture()
        let configuration = try GameRealtimeConfiguration()
        let first = try HeadlessFixture(
            configuration: configuration,
            inputMode: .manual
        )
        let second = try HeadlessFixture(
            configuration: configuration,
            inputMode: .manual
        )

        let firstReport = try first.run(ticks: 10_000, input: input)
        let secondReport = try second.run(ticks: 10_000, input: input)
        XCTAssertEqual(firstReport.ticks, 10_000)
        XCTAssertEqual(firstReport.snapshot.tick, 10_000)
        XCTAssertEqual(firstReport, secondReport)
        XCTAssertEqual(
            firstReport.canonicalBytes,
            secondReport.canonicalBytes
        )
        XCTAssertEqual(
            firstReport.deterministicStateHash,
            14_444_244_010_269_301_202
        )

        let automatic = try HeadlessFixture(
            configuration: configuration,
            inputMode: .automatic
        )
        let automaticReport = try automatic.run(
            ticks: 10_000,
            input: input
        )
        XCTAssertNotEqual(
            automaticReport.deterministicStateHash,
            firstReport.deterministicStateHash
        )

        let loot = try first.spawnGroundLoot(
            at: FixedVector2(
                x: FixedPoint(rawValue: 5),
                y: FixedPoint(rawValue: 7)
            )
        )
        try first.setHealth(20, for: loot)
        try first.setHealth(19, for: loot)
        try first.setHealth(0, for: loot)
        XCTAssertThrowsError(try first.setHealth(10, for: loot))

        var lifecycle = FixedTickAccumulator()
        var tickCount = 0
        _ = lifecycle.consume(
            elapsed: TickPolicy.standardV1.fixedStep
        ) { _ in
            tickCount += 1
        }
        lifecycle.transition(to: .paused)
        let paused = lifecycle.consume(elapsed: .seconds(20)) { _ in
            tickCount += 1
        }
        lifecycle.transition(to: .background)
        let background = lifecycle.consume(elapsed: .seconds(20)) { _ in
            tickCount += 1
        }
        lifecycle.transition(to: .active)
        _ = lifecycle.consume(
            elapsed: TickPolicy.standardV1.fixedStep
        ) { _ in
            tickCount += 1
        }
        lifecycle.transition(to: .faulted)
        let faulted = lifecycle.consume(elapsed: .seconds(20)) { _ in
            tickCount += 1
        }
        XCTAssertEqual(paused.executedTicks, 0)
        XCTAssertEqual(background.executedTicks, 0)
        XCTAssertEqual(faulted.executedTicks, 0)
        XCTAssertEqual(tickCount, 2)

        let session = try GameRealtimeEngineSession(
            configuration: configuration,
            initialState: CanonicalWorldState(seed: 42)
        )
        try await session.submit(input)
        _ = try await session.advanceOneTick()
        let valid = try await session.snapshot()
        var corruptBytes = valid.canonicalBytes
        corruptBytes[corruptBytes.startIndex] ^= 0xFF
        let corrupt = try CanonicalSnapshot(
            schemaID: valid.schemaID,
            profileID: valid.profileID,
            tick: valid.tick,
            epoch: valid.epoch,
            rngStreams: valid.rngStreams,
            canonicalBytes: corruptBytes,
            deterministicStateHash: valid.deterministicStateHash
        )
        do {
            try await session.restore(corrupt)
            XCTFail("expected corrupt facade restore to fail")
        } catch {}
        let afterCorruptRestore = try await session.snapshot()
        XCTAssertEqual(afterCorruptRestore, valid)

    }

    func testQualifiedWorkloadUsesActualEngineStructures() throws {
        let input = try loadInputFixture()
        let configuration = try GameRealtimeConfiguration()
        let qualified = try HeadlessFixture(
            configuration: configuration,
            inputMode: .manual,
            qualified: Self.qualifiedManifest()
        )
        let sample = try qualified.benchmarkSample(
            ticks: 1,
            input: input,
            measureDurations: true
        )
        XCTAssertEqual(sample.metrics.entityCount, 1_600)
        XCTAssertEqual(sample.metrics.componentCount, 2_624)
        XCTAssertEqual(sample.metrics.occupiedBroadphaseCells, 2_048)
        XCTAssertEqual(sample.metrics.candidatePairsPerTick, 16_384)
        XCTAssertEqual(sample.metrics.resolvedPairsPerTick, 4_096)
        XCTAssertEqual(sample.metrics.sweptQueriesPerTick, 512)
        XCTAssertEqual(sample.metrics.sweptHitsPerTick, 512)
        XCTAssertEqual(sample.metrics.collisionWorldBuildsPerTick, 1)
        XCTAssertEqual(sample.metrics.deferredCommandsPerTick, 1_024)
        XCTAssertEqual(sample.metrics.authorityEventsPerTick, 1_024)
        XCTAssertEqual(sample.metrics.acceptedInputFramesPerTick, 128)
        XCTAssertEqual(sample.metrics.queueCount, 1_152)
        XCTAssertEqual(sample.metrics.cacheCount, 0)
        XCTAssertGreaterThan(sample.metrics.checkpointCount, 1)
        XCTAssertGreaterThan(sample.metrics.checkpointBytes, 0)
    }

    private func loadInputFixture() throws -> CombatInputFrame {
        let url = try XCTUnwrap(
            Bundle.module.url(
                forResource: "input",
                withExtension: "json",
                subdirectory: "GameRealtimeDeterminismV1"
            )
        )
        return try JSONDecoder().decode(
            CombatInputFrame.self,
            from: Data(contentsOf: url)
        )
    }

    private static func qualifiedManifest() -> BenchmarkFixtureManifest {
        BenchmarkFixtureManifest(
            schema: "game-realtime-benchmark-fixture-v1",
            fixtureID: "p0-core-1600-v1",
            movingCircles: 512,
            staticAABBBlockers: 256,
            sweptProjectiles: 512,
            stateOnlyEntities: 320,
            occupiedBroadphaseCells: 2_048,
            candidatePairsPerTick: 16_384,
            resolvedPairsPerTick: 4_096,
            deferredCommandsPerTick: 1_024,
            authorityEventsPerTick: 1_024,
            acceptedInputFramesPerTick: 128
        )
    }
}
