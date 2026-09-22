import XCTest
import GameSimulationStateKit
import GameSimulationReducerKit
import GameSimulationProtocolKit
@testable import GameSimulationRuntimeKit

final class GameSimulationRuntimeTests: XCTestCase {
    private struct State: GameSimulationState {
        static let schemaVersion = 1
        var entities = GameEntityRepository()
        var count = 0
    }

    private enum Action: Codable, Equatable, Sendable {
        case increment
    }

    private struct Reducer: GameSimulationReducer, Sendable {
        func reduceAction(
            state: inout State,
            action: Action,
            environment: Void
        ) -> GameSimulationEffect<Action> {
            state.count += 1
            return .none
        }
    }

    private struct ParityState: GameSimulationRuntimeParityState {
        static let schemaVersion = 1
        var entities = GameEntityRepository()
        var simulationRevision: Int64 = 0
        var simulationTick: GameSimulationTick = 0
    }

    private struct ParityReducer: GameSimulationReducer, Sendable {
        func reduceAction(
            state: inout ParityState,
            action: Action,
            environment: Void
        ) -> GameSimulationEffect<Action> {
            state.simulationRevision += 1
            return .none
        }

        func reduceTick(
            state: inout ParityState,
            tick: GameSimulationTick,
            environment: Void
        ) -> GameSimulationEffect<Action> {
            state.simulationRevision += 1
            state.simulationTick = tick
            return .none
        }
    }

    func testUICLIAndAgentDispatchThroughSameCommandPath() async throws {
        for kind in [GameSimulationClientKind.ui, .cli, .agent] {
            let runtime = try makeRuntime()
            let session = try await runtime.connect(
                .init(protocolVersion: 1, clientKind: kind, clientVersion: "1")
            )
            let response = await runtime.submit(
                .init(
                    commandID: "raise",
                    expectedRevision: 0,
                    payload: .dispatch(.increment)
                ),
                sessionID: session
            )

            XCTAssertEqual(
                response.result,
                .accepted(commandID: "raise", revision: 1)
            )
            XCTAssertEqual(response.state?.count, 1)
        }
    }

    func testStaleExpectedRevisionIsRejectedWithoutMutation() async throws {
        let runtime = try makeRuntime()
        let session = try await runtime.connect(validHandshake)
        let response = await runtime.submit(
            .init(
                commandID: "stale",
                expectedRevision: 9,
                payload: .dispatch(.increment)
            ),
            sessionID: session
        )

        XCTAssertEqual(response.result.rejectionCode, "command.revision-conflict")
        let state = await runtime.currentState()
        XCTAssertEqual(state.count, 0)
    }

    func testCommandIDIsIdempotentPerSession() async throws {
        let runtime = try makeRuntime()
        let session = try await runtime.connect(validHandshake)
        let command = GameSimulationCommandEnvelope(
            commandID: "once",
            expectedRevision: 0,
            payload: GameSimulationRuntimeCommand<Action>.dispatch(.increment)
        )

        let first = await runtime.submit(command, sessionID: session)
        let duplicate = await runtime.submit(command, sessionID: session)
        let state = await runtime.currentState()
        let revision = await runtime.currentRevision()

        XCTAssertEqual(duplicate, first)
        XCTAssertEqual(state.count, 1)
        XCTAssertEqual(revision, 1)
    }

    func testMutatingCommandRequiresExpectedRevision() async throws {
        let runtime = try makeRuntime()
        let session = try await runtime.connect(validHandshake)

        let response = await runtime.submit(
            .init(commandID: "missing-revision", payload: .dispatch(.increment)),
            sessionID: session
        )

        XCTAssertEqual(
            response.result.rejectionCode,
            "command.expected-revision-required"
        )
        let state = await runtime.currentState()
        XCTAssertEqual(state.count, 0)
    }

    func testEvictedOrReconnectedMutationCannotExecuteAgain() async throws {
        let runtime = try makeRuntime()
        let firstSession = try await runtime.connect(validHandshake)
        let first = GameSimulationCommandEnvelope(
            commandID: "first",
            expectedRevision: 0,
            payload: GameSimulationRuntimeCommand<Action>.dispatch(.increment)
        )
        _ = await runtime.submit(first, sessionID: firstSession)
        for index in 1 ... 256 {
            _ = await runtime.submit(
                .init(
                    commandID: "filler-\(index)",
                    expectedRevision: Int64(index),
                    payload: .dispatch(.increment)
                ),
                sessionID: firstSession
            )
        }

        let evictedReplay = await runtime.submit(first, sessionID: firstSession)
        XCTAssertEqual(
            evictedReplay.result.rejectionCode,
            "command.revision-conflict"
        )

        await runtime.disconnect(firstSession)
        let secondSession = try await runtime.connect(validHandshake)
        let reconnectedReplay = await runtime.submit(first, sessionID: secondSession)
        XCTAssertEqual(
            reconnectedReplay.result.rejectionCode,
            "command.revision-conflict"
        )
        let state = await runtime.currentState()
        XCTAssertEqual(state.count, 257)
    }

    func testCapabilityIsCheckedIndependentlyOfAgentKind() async throws {
        let runtime = try makeRuntime()
        let session = try await runtime.connect(
            .init(protocolVersion: 1, clientKind: .agent, clientVersion: "1")
        )
        let response = await runtime.submit(
            .init(
                commandID: "cheat",
                expectedRevision: 0,
                requiredCapability: .cheat,
                payload: .dispatch(.increment)
            ),
            sessionID: session
        )

        XCTAssertEqual(response.result.rejectionCode, "protocol.missing-capability")
        let state = await runtime.currentState()
        XCTAssertEqual(state.count, 0)
    }

    func testServerRequiredCapabilityCannotBeBypassedByOmittingEnvelopeDeclaration() async throws {
        let runtime = GameSimulationRuntime(
            machine: try .init(state: State(), environment: (), reducer: Reducer()),
            protocolVersion: 1,
            commandCapability: { command in
                guard case .dispatch = command else { return nil }
                return .cheat
            }
        )
        let session = try await runtime.connect(.init(
            protocolVersion: 1,
            clientKind: .agent,
            clientVersion: "untrusted"
        ))

        let response = await runtime.submit(
            .init(
                commandID: "undeclared-cheat",
                expectedRevision: 0,
                payload: .dispatch(.increment)
            ),
            sessionID: session
        )

        XCTAssertEqual(response.result.rejectionCode, "protocol.missing-capability")
        let state = await runtime.currentState()
        XCTAssertEqual(state.count, 0)
    }

    func testRuntimeCapabilityPolicyOwnsSessionGrants() async throws {
        let runtime = GameSimulationRuntime(
            machine: try .init(state: State(), environment: (), reducer: Reducer()),
            protocolVersion: 1,
            capabilityPolicy: { handshake in
                handshake.clientVersion == "trusted-host" ? [.cheat] : []
            },
            commandCapability: { command in
                guard case .dispatch = command else { return nil }
                return .cheat
            }
        )
        let session = try await runtime.connect(.init(
            protocolVersion: 1,
            clientKind: .cli,
            clientVersion: "trusted-host"
        ))

        let response = await runtime.submit(
            .init(
                commandID: "authorized-cheat",
                expectedRevision: 0,
                payload: .dispatch(.increment)
            ),
            sessionID: session
        )

        XCTAssertNil(response.result.rejectionCode)
        XCTAssertEqual(response.state?.count, 1)
    }

    func testPauseStepSpeedAndSnapshotCommandsShareRevisionRules() async throws {
        let runtime = try makeRuntime()
        let session = try await runtime.connect(validHandshake)

        let paused = await runtime.submit(
            .init(commandID: "pause", expectedRevision: 0, payload: .pause),
            sessionID: session
        )
        XCTAssertEqual(paused.result.revision, 1)

        let stepped = await runtime.submit(
            .init(commandID: "step", expectedRevision: 1, payload: .step(2)),
            sessionID: session
        )
        XCTAssertEqual(stepped.tick, 2)
        XCTAssertEqual(stepped.result.revision, 3)

        let snapshot = await runtime.submit(
            .init(commandID: "snapshot", expectedRevision: 3, payload: .requestSnapshot),
            sessionID: session
        )
        let revision = await runtime.currentRevision()
        XCTAssertNotNil(snapshot.snapshotData)
        XCTAssertEqual(snapshot.result.revision, 3)
        XCTAssertEqual(revision, 3)
    }

    func testControlMutationKeepsParityStateSnapshotable() async throws {
        let runtime = GameSimulationRuntime(
            machine: try GameSimulationMachine(
                state: ParityState(),
                environment: (),
                reducer: ParityReducer()
            ),
            protocolVersion: 1
        )
        let session = try await runtime.connect(validHandshake)

        let paused = await runtime.submit(
            .init(commandID: "pause-parity", expectedRevision: 0, payload: .pause),
            sessionID: session
        )
        XCTAssertEqual(paused.result.revision, 1)
        XCTAssertEqual(paused.state?.simulationRevision, 1)

        let snapshot = await runtime.submit(
            .init(
                commandID: "snapshot-parity",
                expectedRevision: 1,
                payload: .requestSnapshot
            ),
            sessionID: session
        )
        XCTAssertNil(snapshot.result.rejectionCode)
        XCTAssertNotNil(snapshot.snapshotData)
    }

    func testControlMutationRevisionOverflowIsRejectedWithoutPausing() async throws {
        let runtime = GameSimulationRuntime(
            machine: try .init(
                state: State(),
                environment: (),
                reducer: Reducer(),
                configuration: .init(revision: .max)
            ),
            protocolVersion: 1
        )
        let session = try await runtime.connect(validHandshake)

        let paused = await runtime.submit(
            .init(commandID: "pause-max", expectedRevision: .max, payload: .pause),
            sessionID: session
        )
        XCTAssertEqual(paused.result.rejectionCode, "runtime.revision-overflow")

        let snapshot = await runtime.submit(
            .init(commandID: "snapshot-max", payload: .requestSnapshot),
            sessionID: session
        )
        let data = try XCTUnwrap(snapshot.snapshotData)
        let envelope = try JSONDecoder().decode(
            GameSimulationSnapshotEnvelope<State, Action>.self,
            from: data
        )
        XCTAssertFalse(envelope.isPaused)
        XCTAssertEqual(envelope.revision, .max)
    }

    private var validHandshake: GameSimulationHandshake {
        .init(protocolVersion: 1, clientKind: .test, clientVersion: "1")
    }

    private func makeRuntime() throws -> GameSimulationRuntime<Reducer> {
        GameSimulationRuntime(
            machine: try .init(state: State(), environment: (), reducer: Reducer()),
            protocolVersion: 1
        )
    }
}
