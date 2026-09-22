import XCTest
@testable import GameSimulationProtocolKit

final class GameSimulationProtocolTests: XCTestCase {
    private enum Action: String, Codable, Equatable, Sendable {
        case increment
    }

    func testEveryClientKindUsesTheSameHandshakeAndCapabilityRules() throws {
        for kind in GameSimulationClientKind.allCases {
            var validator = GameSimulationProtocolValidator(
                protocolVersion: 1,
                maximumMessageBytes: 1_024
            )
            try validator.acceptHandshake(
                .init(protocolVersion: 1, clientKind: kind, clientVersion: "1.0")
            )

            XCTAssertEqual(validator.clientKind, kind)
            XCTAssertThrowsError(
                try validator.validateCommand(
                    requiredCapability: .cheat,
                    encodedByteCount: 10
                )
            ) {
                XCTAssertEqual(
                    $0 as? GameSimulationProtocolError,
                    .missingCapability(.cheat)
                )
            }
        }
    }

    func testCommandBeforeHandshakeAndVersionMismatchAreRejected() {
        var validator = GameSimulationProtocolValidator(protocolVersion: 3)
        XCTAssertThrowsError(
            try validator.validateCommand(requiredCapability: nil, encodedByteCount: 1)
        ) {
            XCTAssertEqual($0 as? GameSimulationProtocolError, .handshakeRequired)
        }
        XCTAssertThrowsError(
            try validator.acceptHandshake(
                .init(protocolVersion: 2, clientKind: .cli, clientVersion: "1")
            )
        ) {
            XCTAssertEqual(
                $0 as? GameSimulationProtocolError,
                .versionMismatch(expected: 3, received: 2)
            )
        }
    }

    func testGrantedCapabilityAndMessageLimitAreValidatedSeparately() throws {
        var validator = GameSimulationProtocolValidator(
            protocolVersion: 1,
            maximumMessageBytes: 32,
            grantedCapabilities: [.debug]
        )
        try validator.acceptHandshake(
            .init(protocolVersion: 1, clientKind: .agent, clientVersion: "1")
        )
        XCTAssertNoThrow(
            try validator.validateCommand(requiredCapability: .debug, encodedByteCount: 32)
        )
        XCTAssertThrowsError(
            try validator.validateCommand(requiredCapability: nil, encodedByteCount: 33)
        ) {
            XCTAssertEqual(
                $0 as? GameSimulationProtocolError,
                .messageTooLarge(maximum: 32, received: 33)
            )
        }
    }

    func testCommandEnvelopeRoundTripsExpectedRevisionAndPayload() throws {
        let envelope = GameSimulationCommandEnvelope(
            commandID: "command-1",
            expectedRevision: 7,
            requiredCapability: nil,
            payload: GameSimulationRuntimeCommand<Action>.dispatch(.increment)
        )

        let decoded = try JSONDecoder().decode(
            GameSimulationCommandEnvelope<GameSimulationRuntimeCommand<Action>>.self,
            from: JSONEncoder().encode(envelope)
        )

        XCTAssertEqual(decoded, envelope)
    }

    func testCommandResultHasStableRejectionCode() {
        let result = GameSimulationCommandResult.rejected(
            commandID: "bad",
            revision: 4,
            code: "command.revision-conflict",
            message: "expected 3"
        )
        XCTAssertEqual(result.rejectionCode, "command.revision-conflict")
        XCTAssertEqual(result.revision, 4)
    }

    func testRevisionTrackerRejectsGapWithoutAdvancing() throws {
        var tracker = GameSimulationRevisionTracker(lastRevision: 4)
        XCTAssertThrowsError(try tracker.accept(6)) {
            XCTAssertEqual(
                $0 as? GameSimulationProtocolError,
                .revisionGap(expected: 5, received: 6)
            )
        }
        XCTAssertEqual(tracker.lastRevision, 4)
        try tracker.accept(5)
        XCTAssertEqual(tracker.lastRevision, 5)
    }

    func testRevisionTrackerRejectsOverflowWithoutTrap() {
        var tracker = GameSimulationRevisionTracker(lastRevision: .max)

        XCTAssertThrowsError(try tracker.accept(.max)) {
            XCTAssertEqual($0 as? GameSimulationProtocolError, .revisionOverflow)
        }
        XCTAssertEqual(tracker.lastRevision, .max)
    }
}
