import Foundation
import GameRealtimeProtocolKit
import GameRealtimeRuntimeKit
import GameRealtimeStateKit
import XCTest

final class DeterminismTests: XCTestCase {
    func testCanonicalBytesAndRNGAreRepeatable() throws {
        let profile = DeterminismProfile.v1
        XCTAssertEqual(
            profile.schemaID,
            "game-realtime-canonical-state-v1"
        )
        XCTAssertEqual(
            profile.profileID,
            "game-realtime-determinism-v1"
        )
        XCTAssertEqual(profile.byteOrder, "little-endian")
        XCTAssertEqual(profile.fixedPointScale, 1_024)
        XCTAssertEqual(profile.stateHashAlgorithmID, "fnv1a64-v1")
        XCTAssertEqual(profile.rngAlgorithmID, "splitmix64-v1")

        let state = CanonicalWorldState(seed: 42)
        let codec = CanonicalSnapshotCodec(profile: profile)
        let first = try codec.encode(
            state: state,
            rng: [.simulation: DeterministicRNG(seed: 42)]
        )
        let second = try codec.encode(
            state: state,
            rng: [.simulation: DeterministicRNG(seed: 42)]
        )
        XCTAssertEqual(first.canonicalBytes, second.canonicalBytes)
        XCTAssertEqual(
            first.deterministicStateHash,
            second.deterministicStateHash
        )
        XCTAssertEqual(first.canonicalBytes.count, 165)
        XCTAssertEqual(first.canonicalBytes.prefix(4), Data([32, 0, 0, 0]))
        XCTAssertEqual(first.canonicalBytes[120], 0)
        XCTAssertEqual(first.deterministicStateHash, 0xBFF2_40B0_6E6A_6262)

        var ascendingStreams: [RNGStreamID: DeterministicRNG] = [:]
        ascendingStreams[.simulation] = DeterministicRNG(seed: 42)
        ascendingStreams[.combat] = DeterministicRNG(seed: 99)
        var descendingStreams: [RNGStreamID: DeterministicRNG] = [:]
        descendingStreams[.combat] = DeterministicRNG(seed: 99)
        descendingStreams[.simulation] = DeterministicRNG(seed: 42)
        let ascending = try codec.encode(
            state: state,
            rng: ascendingStreams
        )
        let descending = try codec.encode(
            state: state,
            rng: descendingStreams
        )
        XCTAssertEqual(ascending.canonicalBytes, descending.canonicalBytes)
        XCTAssertEqual(ascending.deterministicStateHash, descending.deterministicStateHash)
        XCTAssertEqual(
            ascending.rngStreams.map(\.streamID),
            [RNGStreamID.simulation.rawValue, RNGStreamID.combat.rawValue]
        )

        var zeroSeed = DeterministicRNG(seed: 0)
        XCTAssertEqual(zeroSeed.next(), 0xE220_A839_7B1D_CDAF)
        XCTAssertEqual(zeroSeed.state, 0x9E37_79B9_7F4A_7C15)
        var seedFortyTwo = DeterministicRNG(seed: 42)
        XCTAssertEqual(seedFortyTwo.next(), 0xBDD7_3226_2FEB_6E95)
        let simulationA = DeterministicRNG(seed: 42).stream(.simulation)
        let simulationB = DeterministicRNG(seed: 42).stream(.simulation)
        let combat = DeterministicRNG(seed: 42).stream(.combat)
        XCTAssertEqual(simulationA.state, simulationB.state)
        XCTAssertNotEqual(simulationA.state, combat.state)

        var firstTenThousand = DeterministicRNG(seed: 42)
        var secondTenThousand = DeterministicRNG(seed: 42)
        for _ in 0 ..< 10_000 {
            XCTAssertEqual(firstTenThousand.next(), secondTenThousand.next())
        }
        XCTAssertEqual(firstTenThousand.state, 0x5702_DDFC_4D8E_F47A)
        let tenThousandState = CanonicalWorldState(tick: 10_000, seed: 42)
        let tenThousandSnapshot = try codec.encode(
            state: tenThousandState,
            rng: [.simulation: firstTenThousand]
        )
        XCTAssertEqual(
            tenThousandSnapshot.deterministicStateHash,
            0xC697_BCF4_C112_B29E
        )

        var restoredState = CanonicalWorldState(tick: 7, epoch: 8, seed: 9)
        var restoredRNG: [RNGStreamID: DeterministicRNG] = [
            .combat: DeterministicRNG(seed: 9),
        ]
        try codec.restore(
            first,
            state: &restoredState,
            rng: &restoredRNG
        )
        XCTAssertEqual(restoredState.tick, state.tick)
        XCTAssertEqual(restoredState.epoch, state.epoch)
        XCTAssertEqual(restoredState.seed, state.seed)
        XCTAssertEqual(restoredRNG.count, 1)
        XCTAssertEqual(restoredRNG[.simulation]?.state, 42)

        var corruptedBytes = first.canonicalBytes
        corruptedBytes[0] ^= 0xFF
        let corrupted = try CanonicalSnapshot(
            schemaID: first.schemaID,
            profileID: first.profileID,
            tick: first.tick,
            epoch: first.epoch,
            rngStreams: first.rngStreams,
            canonicalBytes: corruptedBytes,
            deterministicStateHash: first.deterministicStateHash
        )
        try assertRestoreRejectedWithoutMutation(
            corrupted,
            expected: .deterministicStateHashMismatch(
                expected: first.deterministicStateHash,
                actual: fnv1a64(corruptedBytes)
            ),
            codec: codec
        )

        let wrongSchema = try CanonicalSnapshot(
            schemaID: "game-realtime-canonical-state-v2",
            profileID: first.profileID,
            tick: first.tick,
            epoch: first.epoch,
            rngStreams: first.rngStreams,
            canonicalBytes: first.canonicalBytes,
            deterministicStateHash: first.deterministicStateHash
        )
        try assertRestoreRejectedWithoutMutation(
            wrongSchema,
            expected: .schemaMismatch(
                expected: profile.schemaID,
                actual: wrongSchema.schemaID
            ),
            codec: codec
        )

        let wrongProfile = try CanonicalSnapshot(
            schemaID: first.schemaID,
            profileID: "game-realtime-determinism-v2",
            tick: first.tick,
            epoch: first.epoch,
            rngStreams: first.rngStreams,
            canonicalBytes: first.canonicalBytes,
            deterministicStateHash: first.deterministicStateHash
        )
        try assertRestoreRejectedWithoutMutation(
            wrongProfile,
            expected: .profileMismatch(
                expected: profile.profileID,
                actual: wrongProfile.profileID
            ),
            codec: codec
        )
    }

    func testCodecRejectsEveryMislabelledV1ProfileAndBoundsUTF8() throws {
        let standard = DeterminismProfile.v1
        let standardSnapshot = try CanonicalSnapshotCodec(
            profile: standard
        ).encode(
            state: CanonicalWorldState(seed: 42),
            rng: [.simulation: DeterministicRNG(seed: 42)]
        )
        let invalidProfiles: [(DeterminismProfile, String)] = [
            (
                DeterminismProfile(
                    schemaID: "game-realtime-canonical-state-v2",
                    profileID: standard.profileID,
                    byteOrder: standard.byteOrder,
                    fixedPointScale: standard.fixedPointScale,
                    stateHashAlgorithmID: standard.stateHashAlgorithmID,
                    rngAlgorithmID: standard.rngAlgorithmID
                ),
                "schemaIDMismatch(expected: \"game-realtime-canonical-state-v1\", actual: \"game-realtime-canonical-state-v2\")"
            ),
            (
                DeterminismProfile(
                    schemaID: standard.schemaID,
                    profileID: "game-realtime-determinism-v2",
                    byteOrder: standard.byteOrder,
                    fixedPointScale: standard.fixedPointScale,
                    stateHashAlgorithmID: standard.stateHashAlgorithmID,
                    rngAlgorithmID: standard.rngAlgorithmID
                ),
                "profileIDMismatch(expected: \"game-realtime-determinism-v1\", actual: \"game-realtime-determinism-v2\")"
            ),
            (
                DeterminismProfile(
                    schemaID: standard.schemaID,
                    profileID: standard.profileID,
                    byteOrder: "big-endian",
                    fixedPointScale: standard.fixedPointScale,
                    stateHashAlgorithmID: standard.stateHashAlgorithmID,
                    rngAlgorithmID: standard.rngAlgorithmID
                ),
                "byteOrderMismatch(expected: \"little-endian\", actual: \"big-endian\")"
            ),
            (
                DeterminismProfile(
                    schemaID: standard.schemaID,
                    profileID: standard.profileID,
                    byteOrder: standard.byteOrder,
                    fixedPointScale: 7,
                    stateHashAlgorithmID: standard.stateHashAlgorithmID,
                    rngAlgorithmID: standard.rngAlgorithmID
                ),
                "fixedPointScaleMismatch(expected: 1024, actual: 7)"
            ),
            (
                DeterminismProfile(
                    schemaID: standard.schemaID,
                    profileID: standard.profileID,
                    byteOrder: standard.byteOrder,
                    fixedPointScale: standard.fixedPointScale,
                    stateHashAlgorithmID: "sha256-v1",
                    rngAlgorithmID: standard.rngAlgorithmID
                ),
                "stateHashAlgorithmMismatch(expected: \"fnv1a64-v1\", actual: \"sha256-v1\")"
            ),
            (
                DeterminismProfile(
                    schemaID: standard.schemaID,
                    profileID: standard.profileID,
                    byteOrder: standard.byteOrder,
                    fixedPointScale: standard.fixedPointScale,
                    stateHashAlgorithmID: standard.stateHashAlgorithmID,
                    rngAlgorithmID: "system-random-v1"
                ),
                "rngAlgorithmMismatch(expected: \"splitmix64-v1\", actual: \"system-random-v1\")"
            ),
        ]

        for (profile, expectedDescription) in invalidProfiles {
            let invalidCodec = CanonicalSnapshotCodec(profile: profile)
            XCTAssertThrowsError(
                try invalidCodec.encode(
                    state: CanonicalWorldState(seed: 42),
                    rng: [.simulation: DeterministicRNG(seed: 42)]
                )
            ) { error in
                XCTAssertEqual(
                    String(describing: type(of: error)),
                    "DeterminismProfileError"
                )
                XCTAssertEqual(String(describing: error), expectedDescription)
            }

            var retainedState = CanonicalWorldState(tick: 7, epoch: 8, seed: 9)
            var retainedRNG: [RNGStreamID: DeterministicRNG] = [
                .combat: DeterministicRNG(seed: 9),
            ]
            XCTAssertThrowsError(
                try invalidCodec.restore(
                    standardSnapshot,
                    state: &retainedState,
                    rng: &retainedRNG
                )
            ) { error in
                XCTAssertEqual(
                    String(describing: type(of: error)),
                    "DeterminismProfileError"
                )
                XCTAssertEqual(String(describing: error), expectedDescription)
            }
            XCTAssertEqual(retainedState.tick, 7)
            XCTAssertEqual(retainedState.epoch, 8)
            XCTAssertEqual(retainedState.seed, 9)
            XCTAssertEqual(retainedRNG.count, 1)
            XCTAssertEqual(retainedRNG[.combat]?.state, 9)
        }

        let limit = RealtimeLimits.standardV1.canonicalSnapshotBytes
        let oversized = DeterminismProfile(
            schemaID: String(repeating: "é", count: limit),
            profileID: standard.profileID,
            byteOrder: standard.byteOrder,
            fixedPointScale: standard.fixedPointScale,
            stateHashAlgorithmID: standard.stateHashAlgorithmID,
            rngAlgorithmID: standard.rngAlgorithmID
        )
        XCTAssertThrowsError(
            try CanonicalSnapshotCodec(profile: oversized).encode(
                state: CanonicalWorldState(seed: 42),
                rng: [.simulation: DeterministicRNG(seed: 42)]
            )
        ) { error in
            guard let capacity = error as? EngineCapacityError else {
                return XCTFail("expected EngineCapacityError, got \(error)")
            }
            XCTAssertEqual(capacity.resource, .canonicalSnapshotBytes)
            XCTAssertEqual(capacity.limit, limit)
            XCTAssertGreaterThan(capacity.attempted, limit)
        }
    }

    func testRestoreErrorsAreGranularAndAtomic() throws {
        let codec = CanonicalSnapshotCodec(profile: .v1)
        let base = try codec.encode(
            state: CanonicalWorldState(seed: 42),
            rng: [.simulation: DeterministicRNG(seed: 42)]
        )

        var staleHashBytes = base.canonicalBytes
        staleHashBytes[0] ^= 0xFF
        let staleHash = try replacingBytes(
            in: base,
            with: staleHashBytes,
            deterministicStateHash: base.deterministicStateHash
        )
        try assertRestoreRejectedWithoutMutation(
            staleHash,
            expectedDescription:
                "deterministicStateHashMismatch(expected: \(base.deterministicStateHash), actual: \(fnv1a64(staleHashBytes)))",
            codec: codec
        )

        var malformedLengthBytes = base.canonicalBytes
        malformedLengthBytes.replaceSubrange(
            0 ..< 4,
            with: [0xFF, 0xFF, 0x00, 0x00]
        )
        try assertRestoreRejectedWithoutMutation(
            try replacingBytes(in: base, with: malformedLengthBytes),
            expectedDescription:
                "malformedLengthPrefix(declared: 65535, remaining: 161)",
            codec: codec
        )

        var invalidOptionalBytes = base.canonicalBytes
        invalidOptionalBytes[120] = 2
        try assertRestoreRejectedWithoutMutation(
            try replacingBytes(in: base, with: invalidOptionalBytes),
            expectedDescription: "invalidOptionalPresenceByte(2)",
            codec: codec
        )

        var trailingBytes = base.canonicalBytes
        trailingBytes.append(0)
        try assertRestoreRejectedWithoutMutation(
            try replacingBytes(in: base, with: trailingBytes),
            expectedDescription: "trailingCanonicalBytes(1)",
            codec: codec
        )

        let twoStreams = try codec.encode(
            state: CanonicalWorldState(seed: 42),
            rng: [
                .simulation: DeterministicRNG(seed: 42),
                .combat: DeterministicRNG(seed: 99),
            ]
        )
        var outOfOrderBytes = twoStreams.canonicalBytes
        replaceUInt64(in: &outOfOrderBytes, at: 149, with: 2)
        replaceUInt64(in: &outOfOrderBytes, at: 165, with: 1)
        try assertRestoreRejectedWithoutMutation(
            try replacingBytes(in: twoStreams, with: outOfOrderBytes),
            expectedDescription:
                "rngStreamOutOfOrder(previous: 2, current: 1)",
            codec: codec
        )

        var duplicateBytes = twoStreams.canonicalBytes
        replaceUInt64(in: &duplicateBytes, at: 165, with: 1)
        try assertRestoreRejectedWithoutMutation(
            try replacingBytes(in: twoStreams, with: duplicateBytes),
            expectedDescription: "duplicateRNGStreamID(1)",
            codec: codec
        )

        var unknownBytes = base.canonicalBytes
        replaceUInt64(in: &unknownBytes, at: 149, with: 99)
        try assertRestoreRejectedWithoutMutation(
            try replacingBytes(in: base, with: unknownBytes),
            expectedDescription: "unknownRNGStreamID(99)",
            codec: codec
        )

        var missingBytes = base.canonicalBytes
        missingBytes.replaceSubrange(145 ..< 149, with: [0, 0, 0, 0])
        missingBytes.removeSubrange(149 ..< missingBytes.endIndex)
        let missing = try replacingBytes(
            in: base,
            with: missingBytes,
            rngStreams: []
        )
        try assertRestoreRejectedWithoutMutation(
            missing,
            expectedDescription: "missingRNGStreamID(1)",
            codec: codec
        )

        var innerSchemaBytes = base.canonicalBytes
        innerSchemaBytes[35] = Character("2").asciiValue!
        try assertRestoreRejectedWithoutMutation(
            try replacingBytes(in: base, with: innerSchemaBytes),
            expectedDescription:
                "innerSchemaMismatch(expected: \"game-realtime-canonical-state-v1\", actual: \"game-realtime-canonical-state-v2\")",
            codec: codec
        )

        var innerProfileBytes = base.canonicalBytes
        innerProfileBytes[67] = Character("2").asciiValue!
        try assertRestoreRejectedWithoutMutation(
            try replacingBytes(in: base, with: innerProfileBytes),
            expectedDescription:
                "innerProfileMismatch(expected: \"game-realtime-determinism-v1\", actual: \"game-realtime-determinism-v2\")",
            codec: codec
        )
    }

    func testStreamDerivationUsesExactVectors() {
        XCTAssertEqual(
            DeterministicRNG(seed: 42).stream(.simulation).state,
            0xBDD7_3226_2FEB_6E95
        )
        XCTAssertEqual(
            DeterministicRNG(seed: 42).stream(.combat).state,
            0xD963_9A00_6C85_ADB0
        )
    }

    func testEncodeRequiresSimulationRNGStreamBeforeEmission() throws {
        let codec = CanonicalSnapshotCodec(profile: .v1)
        let state = CanonicalWorldState(tick: 7, epoch: 8, seed: 9)
        let missingSimulationCases: [[RNGStreamID: DeterministicRNG]] = [
            [:],
            [.combat: DeterministicRNG(seed: 99)],
        ]

        for streams in missingSimulationCases {
            XCTAssertThrowsError(
                try codec.encode(state: state, rng: streams)
            ) { error in
                XCTAssertEqual(
                    error as? SnapshotRestoreError,
                    .missingRNGStreamID(RNGStreamID.simulation.rawValue)
                )
            }
        }

        var reverseInsertionOrder: [RNGStreamID: DeterministicRNG] = [:]
        reverseInsertionOrder[.combat] = DeterministicRNG(seed: 99)
        reverseInsertionOrder[.simulation] = DeterministicRNG(seed: 42)
        let snapshot = try codec.encode(
            state: state,
            rng: reverseInsertionOrder
        )
        XCTAssertEqual(
            snapshot.rngStreams.map(\.streamID),
            [
                RNGStreamID.simulation.rawValue,
                RNGStreamID.combat.rawValue,
            ]
        )

        var restoredState = CanonicalWorldState(seed: 0)
        var restoredRNG: [RNGStreamID: DeterministicRNG] = [:]
        try codec.restore(
            snapshot,
            state: &restoredState,
            rng: &restoredRNG
        )
        XCTAssertEqual(restoredState.tick, state.tick)
        XCTAssertEqual(restoredState.epoch, state.epoch)
        XCTAssertEqual(restoredState.seed, state.seed)
        XCTAssertEqual(restoredRNG[.simulation]?.state, 42)
        XCTAssertEqual(restoredRNG[.combat]?.state, 99)
    }

    private func assertRestoreRejectedWithoutMutation(
        _ snapshot: CanonicalSnapshot,
        expected: SnapshotRestoreError,
        codec: CanonicalSnapshotCodec,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        var retainedState = CanonicalWorldState(tick: 7, epoch: 8, seed: 9)
        var retainedRNG: [RNGStreamID: DeterministicRNG] = [
            .combat: DeterministicRNG(seed: 9),
        ]

        XCTAssertThrowsError(
            try codec.restore(
                snapshot,
                state: &retainedState,
                rng: &retainedRNG
            ),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(
                error as? SnapshotRestoreError,
                expected,
                file: file,
                line: line
            )
        }
        XCTAssertEqual(retainedState.tick, 7, file: file, line: line)
        XCTAssertEqual(retainedState.epoch, 8, file: file, line: line)
        XCTAssertEqual(retainedState.seed, 9, file: file, line: line)
        XCTAssertEqual(retainedRNG.count, 1, file: file, line: line)
        XCTAssertEqual(
            retainedRNG[.combat]?.state,
            9,
            file: file,
            line: line
        )
    }

    private func assertRestoreRejectedWithoutMutation(
        _ snapshot: CanonicalSnapshot,
        expectedDescription: String,
        codec: CanonicalSnapshotCodec,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        var retainedState = CanonicalWorldState(tick: 7, epoch: 8, seed: 9)
        var retainedRNG: [RNGStreamID: DeterministicRNG] = [
            .combat: DeterministicRNG(seed: 9),
        ]

        XCTAssertThrowsError(
            try codec.restore(
                snapshot,
                state: &retainedState,
                rng: &retainedRNG
            ),
            file: file,
            line: line
        ) { error in
            XCTAssertTrue(
                error is SnapshotRestoreError,
                "expected SnapshotRestoreError, got \(error)",
                file: file,
                line: line
            )
            XCTAssertEqual(
                String(describing: error),
                expectedDescription,
                file: file,
                line: line
            )
        }
        XCTAssertEqual(retainedState.tick, 7, file: file, line: line)
        XCTAssertEqual(retainedState.epoch, 8, file: file, line: line)
        XCTAssertEqual(retainedState.seed, 9, file: file, line: line)
        XCTAssertEqual(retainedRNG.count, 1, file: file, line: line)
        XCTAssertEqual(
            retainedRNG[.combat]?.state,
            9,
            file: file,
            line: line
        )
    }

    private func replacingBytes(
        in snapshot: CanonicalSnapshot,
        with bytes: Data,
        rngStreams: [RNGStreamSnapshot]? = nil,
        deterministicStateHash: UInt64? = nil
    ) throws -> CanonicalSnapshot {
        try CanonicalSnapshot(
            schemaID: snapshot.schemaID,
            profileID: snapshot.profileID,
            tick: snapshot.tick,
            epoch: snapshot.epoch,
            rngStreams: rngStreams ?? snapshot.rngStreams,
            canonicalBytes: bytes,
            deterministicStateHash: deterministicStateHash ?? fnv1a64(bytes)
        )
    }

    private func replaceUInt64(
        in data: inout Data,
        at offset: Int,
        with value: UInt64
    ) {
        for byteOffset in 0 ..< 8 {
            data[offset + byteOffset] = UInt8(
                truncatingIfNeeded: value >> UInt64(byteOffset * 8)
            )
        }
    }

    private func fnv1a64(_ data: Data) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in data {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return hash
    }
}
