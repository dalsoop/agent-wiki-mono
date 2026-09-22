import Foundation
import XCTest
@testable import GameRealtimeProtocolKit

final class ProtocolValueTests: XCTestCase {
    func testInputAndCapacityAreVersioned() throws {
        let zero = FixedPoint(rawValue: 0)
        let entity = EntityHandle(index: 1, generation: 1)
        let input = try CombatInputFrame(
            targetTick: 3,
            controlledEntity: entity,
            sequence: 1,
            source: .manual,
            move: FixedVector2(x: zero, y: zero),
            aim: FixedVector2(x: zero, y: zero),
            buttons: []
        )

        XCTAssertEqual(input.contractVersion, 1)
        XCTAssertEqual(
            EngineCapacityError(resource: .entities, limit: 8, attempted: 9),
            .init(resource: .entities, limit: 8, attempted: 9)
        )

        XCTAssertThrowsError(
            try CombatInputFrame(
                contractVersion: 2,
                targetTick: 3,
                controlledEntity: entity,
                sequence: 2,
                source: .manual,
                move: input.move,
                aim: input.aim,
                buttons: []
            )
        ) { error in
            XCTAssertEqual(
                error as? EngineConfigurationError,
                .unsupportedInputContractVersion(2)
            )
        }

        XCTAssertThrowsError(
            try CombatInputFrame(
                targetTick: 3,
                controlledEntity: entity,
                sequence: 3,
                source: .manual,
                move: FixedVector2(
                    x: FixedPoint(rawValue: FixedPoint.scale + 1),
                    y: zero
                ),
                aim: input.aim,
                buttons: []
            )
        ) { error in
            XCTAssertEqual(
                error as? EngineConfigurationError,
                .inputCoordinateOutOfRange(
                    component: .moveX,
                    rawValue: FixedPoint.scale + 1
                )
            )
        }

        XCTAssertThrowsError(
            try CombatInputFrame(
                targetTick: 3,
                controlledEntity: entity,
                sequence: 4,
                source: .manual,
                move: input.move,
                aim: input.aim,
                buttons: CombatInputButtons(rawValue: 1 << 4)
            )
        ) { error in
            XCTAssertEqual(
                error as? EngineConfigurationError,
                .unsupportedInputButtons(rawValue: 1 << 4)
            )
        }

        XCTAssertEqual(input.targetTick, 3)
        XCTAssertEqual(input.controlledEntity, entity)
        XCTAssertEqual(input.sequence, 1)
        XCTAssertEqual(input.source, .manual)
        XCTAssertEqual(input.move, FixedVector2(x: zero, y: zero))
        XCTAssertEqual(input.aim, FixedVector2(x: zero, y: zero))
        XCTAssertEqual(input.buttons, [])
    }

    func testInputBoundariesAndButtonBitsAreAccepted() throws {
        let minimum = FixedPoint(rawValue: -FixedPoint.scale)
        let maximum = FixedPoint(rawValue: FixedPoint.scale)
        let allButtons: CombatInputButtons = [
            .primaryAction,
            .secondaryAction,
            .dodge,
            .interact,
        ]

        let input = try CombatInputFrame(
            targetTick: 0,
            controlledEntity: EntityHandle(index: 0, generation: 0),
            sequence: 0,
            source: .remote,
            move: FixedVector2(x: minimum, y: maximum),
            aim: FixedVector2(x: maximum, y: minimum),
            buttons: allButtons
        )

        XCTAssertEqual(input.move.x, minimum)
        XCTAssertEqual(input.move.y, maximum)
        XCTAssertEqual(input.aim.x, maximum)
        XCTAssertEqual(input.aim.y, minimum)
        XCTAssertEqual(input.buttons.rawValue, 0b1111)
    }

    func testRealtimeLimitsStandardV1HasExactValues() {
        let limits = RealtimeLimits.standardV1

        XCTAssertEqual(limits.totalEntities, 8_192)
        XCTAssertEqual(limits.entitiesPerKind, 4_096)
        XCTAssertEqual(limits.componentSlotsPerKind, 8_192)
        XCTAssertEqual(limits.registeredComponentKinds, 128)
        XCTAssertEqual(limits.stableQueryCacheEntries, 256)
        XCTAssertEqual(limits.deferredCommandsPerTick, 4_096)
        XCTAssertEqual(limits.authorityEventsPerTick, 4_096)
        XCTAssertEqual(limits.queuedInputFrames, 1_024)
        XCTAssertEqual(limits.broadphaseOccupiedCells, 16_384)
        XCTAssertEqual(limits.broadphaseCandidatePairsPerTick, 65_536)
        XCTAssertEqual(limits.resolvedCollisionPairsPerTick, 32_768)
        XCTAssertEqual(limits.solverIterationsPerPair, 4)
        XCTAssertEqual(limits.checkpointRingLength, 120)
        XCTAssertEqual(limits.checkpointRingBytes, 67_108_864)
        XCTAssertEqual(limits.canonicalSnapshotBytes, 524_288)
        XCTAssertEqual(limits.replayInputFrames, 300_000)
        XCTAssertEqual(limits.outboundSnapshots, 8)
    }

    func testCanonicalSnapshotValidatesIdentifiersOrderingAndCapacityWithoutMutation() throws {
        var retained = try makeSnapshot()
        let original = retained

        assertRejectedSnapshotAssignment(
            retained: &retained,
            expected: EngineConfigurationError.emptySnapshotIdentifier(
                .schemaID
            )
        ) {
            try self.makeSnapshot(schemaID: "")
        }
        XCTAssertEqual(retained, original)

        assertRejectedSnapshotAssignment(
            retained: &retained,
            expected: EngineConfigurationError.emptySnapshotIdentifier(
                .profileID
            )
        ) {
            try self.makeSnapshot(profileID: "")
        }
        XCTAssertEqual(retained, original)

        assertRejectedSnapshotAssignment(
            retained: &retained,
            expected: EngineConfigurationError.duplicateRNGStreamID(1)
        ) {
            try self.makeSnapshot(
                rngStreams: [
                    RNGStreamSnapshot(streamID: 1, state: 11),
                    RNGStreamSnapshot(streamID: 1, state: 22),
                ]
            )
        }
        XCTAssertEqual(retained, original)

        let limit = RealtimeLimits.standardV1.canonicalSnapshotBytes
        assertRejectedSnapshotAssignment(
            retained: &retained,
            expected: EngineCapacityError(
                resource: .canonicalSnapshotBytes,
                limit: limit,
                attempted: limit + 1
            )
        ) {
            try self.makeSnapshot(canonicalByteCount: limit + 1)
        }
        XCTAssertEqual(retained, original)
    }

    func testCanonicalSnapshotSortsRNGStreamsAndEnforcesExactByteLimit() throws {
        let limit = RealtimeLimits.standardV1.canonicalSnapshotBytes
        let snapshot = try makeSnapshot(
            rngStreams: [
                RNGStreamSnapshot(streamID: 2, state: 22),
                RNGStreamSnapshot(streamID: 1, state: 11),
            ],
            canonicalByteCount: limit
        )

        XCTAssertEqual(snapshot.rngStreams.map(\.streamID), [1, 2])
        XCTAssertEqual(snapshot.rngStreams.map(\.state), [11, 22])
        XCTAssertEqual(snapshot.canonicalBytes.count, 524_288)

        XCTAssertThrowsError(
            try makeSnapshot(canonicalByteCount: limit + 1)
        ) { error in
            XCTAssertEqual(
                error as? EngineCapacityError,
                EngineCapacityError(
                    resource: .canonicalSnapshotBytes,
                    limit: 524_288,
                    attempted: 524_289
                )
            )
        }
    }

    func testTypedDiagnosticsAreStableValues() {
        XCTAssertEqual(
            EngineCapacityError(
                resource: .queuedInputFrames,
                limit: 1_024,
                attempted: 1_025
            ),
            EngineCapacityError(
                resource: .queuedInputFrames,
                limit: 1_024,
                attempted: 1_025
            )
        )
        XCTAssertEqual(
            EngineOwnershipError.reentrantMutation,
            EngineOwnershipError.reentrantMutation
        )
    }

    func testCodableDecodingCannotBypassValidation() throws {
        let validInput = try makeInput()

        try assertMalformedInput(
            validInput,
            expected: .unsupportedInputContractVersion(2)
        ) { object in
            object["contractVersion"] = 2
        }

        let coordinateCases: [
            (
                EngineConfigurationError.InputCoordinate,
                EngineConfigurationError
            )
        ] = [
            (
                .moveX,
                .inputCoordinateOutOfRange(
                    component: .moveX,
                    rawValue: FixedPoint.scale + 1
                )
            ),
            (
                .moveY,
                .inputCoordinateOutOfRange(
                    component: .moveY,
                    rawValue: FixedPoint.scale + 1
                )
            ),
            (
                .aimX,
                .inputCoordinateOutOfRange(
                    component: .aimX,
                    rawValue: FixedPoint.scale + 1
                )
            ),
            (
                .aimY,
                .inputCoordinateOutOfRange(
                    component: .aimY,
                    rawValue: FixedPoint.scale + 1
                )
            ),
        ]
        for (component, expected) in coordinateCases {
            try assertMalformedInput(validInput, expected: expected) {
                object in
                try self.replaceInputCoordinate(
                    component,
                    rawValue: FixedPoint.scale + 1,
                    in: &object
                )
            }
        }

        try assertMalformedInput(
            validInput,
            expected: .unsupportedInputButtons(rawValue: 1 << 4)
        ) { object in
            object["buttons"] = 1 << 4
        }
    }

    func testCodableRejectsEveryMalformedSnapshotBoundary() throws {
        let validSnapshot = try makeSnapshot()

        try assertMalformedSnapshot(
            validSnapshot,
            expected: EngineConfigurationError.emptySnapshotIdentifier(
                .schemaID
            )
        ) { object in
            object["schemaID"] = ""
        }
        try assertMalformedSnapshot(
            validSnapshot,
            expected: EngineConfigurationError.emptySnapshotIdentifier(
                .profileID
            )
        ) { object in
            object["profileID"] = ""
        }
        try assertMalformedSnapshot(
            validSnapshot,
            expected: EngineConfigurationError.duplicateRNGStreamID(1)
        ) { object in
            object["rngStreams"] = [
                ["streamID": 1, "state": 11],
                ["streamID": 1, "state": 22],
            ]
        }

        let limit = RealtimeLimits.standardV1.canonicalSnapshotBytes
        try assertMalformedSnapshot(
            validSnapshot,
            expected: EngineCapacityError(
                resource: .canonicalSnapshotBytes,
                limit: limit,
                attempted: limit + 1
            )
        ) { object in
            object["canonicalBytes"] = Data(
                repeating: 0,
                count: limit + 1
            ).base64EncodedString()
        }
    }

    private func makeInput() throws -> CombatInputFrame {
        let zero = FixedPoint(rawValue: 0)
        return try CombatInputFrame(
            targetTick: 1,
            controlledEntity: EntityHandle(index: 0, generation: 0),
            sequence: 1,
            source: .automatic,
            move: FixedVector2(x: zero, y: zero),
            aim: FixedVector2(x: zero, y: zero),
            buttons: [.primaryAction]
        )
    }

    private func makeSnapshot(
        schemaID: String = "game-realtime-canonical-v1",
        profileID: String = "determinism-v1",
        rngStreams: [RNGStreamSnapshot] = [
            RNGStreamSnapshot(streamID: 1, state: 11),
            RNGStreamSnapshot(streamID: 2, state: 22),
        ],
        canonicalByteCount: Int = 2
    ) throws -> CanonicalSnapshot {
        try CanonicalSnapshot(
            schemaID: schemaID,
            profileID: profileID,
            tick: 7,
            epoch: 2,
            rngStreams: rngStreams,
            canonicalBytes: Data(repeating: 0, count: canonicalByteCount),
            deterministicStateHash: 42
        )
    }

    private func assertRejectedSnapshotAssignment<Failure>(
        retained: inout CanonicalSnapshot,
        expected: Failure,
        constructing: () throws -> CanonicalSnapshot,
        file: StaticString = #filePath,
        line: UInt = #line
    ) where Failure: Error & Equatable {
        let original = retained
        do {
            retained = try constructing()
            XCTFail("Expected snapshot construction to fail", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? Failure, expected, file: file, line: line)
        }
        XCTAssertEqual(retained, original, file: file, line: line)
    }

    private func assertMalformedInput(
        _ input: CombatInputFrame,
        expected: EngineConfigurationError,
        mutate: (inout [String: Any]) throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let data = try mutatedJSONData(input, mutate: mutate)
        assertDecodingError(
            CombatInputFrame.self,
            from: data,
            expected: expected,
            file: file,
            line: line
        )
    }

    private func assertMalformedSnapshot<Failure>(
        _ snapshot: CanonicalSnapshot,
        expected: Failure,
        mutate: (inout [String: Any]) throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws where Failure: Error & Equatable {
        let data = try mutatedJSONData(snapshot, mutate: mutate)
        assertDecodingError(
            CanonicalSnapshot.self,
            from: data,
            expected: expected,
            file: file,
            line: line
        )
    }

    private func assertDecodingError<Value, Failure>(
        _ type: Value.Type,
        from data: Data,
        expected: Failure,
        file: StaticString,
        line: UInt
    ) where Value: Decodable, Failure: Error & Equatable {
        XCTAssertThrowsError(
            try JSONDecoder().decode(type, from: data),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(
                error as? Failure,
                expected,
                file: file,
                line: line
            )
        }
    }

    private func mutatedJSONData<Value>(
        _ value: Value,
        mutate: (inout [String: Any]) throws -> Void
    ) throws -> Data where Value: Encodable {
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: JSONEncoder().encode(value)
            ) as? [String: Any]
        )
        try mutate(&object)
        return try JSONSerialization.data(withJSONObject: object)
    }

    private func replaceInputCoordinate(
        _ component: EngineConfigurationError.InputCoordinate,
        rawValue: Int32,
        in object: inout [String: Any]
    ) throws {
        let vectorKey: String
        let coordinateKey: String
        switch component {
        case .moveX:
            vectorKey = "move"
            coordinateKey = "x"
        case .moveY:
            vectorKey = "move"
            coordinateKey = "y"
        case .aimX:
            vectorKey = "aim"
            coordinateKey = "x"
        case .aimY:
            vectorKey = "aim"
            coordinateKey = "y"
        }

        var vector = try XCTUnwrap(
            object[vectorKey] as? [String: Any]
        )
        var coordinate = try XCTUnwrap(
            vector[coordinateKey] as? [String: Any]
        )
        coordinate["rawValue"] = Int(rawValue)
        vector[coordinateKey] = coordinate
        object[vectorKey] = vector
    }
}
