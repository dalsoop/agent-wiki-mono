import Foundation
import GameSimulationStateKit
import GameSimulationReducerKit
import GameSimulationProtocolKit

public struct GameSimulationSessionID: RawRepresentable, Codable, Hashable, Sendable {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static func random() -> Self {
        Self(rawValue: UUID().uuidString.lowercased())
    }
}

public struct GameSimulationRuntimeResponse<State, Action>: Codable, Equatable, Sendable
where State: GameSimulationBaseState,
      Action: Codable & Equatable & Sendable {
    public var result: GameSimulationCommandResult
    public var state: State?
    public var tick: GameSimulationTick
    public var snapshotData: Data?

    public init(
        result: GameSimulationCommandResult,
        state: State?,
        tick: GameSimulationTick,
        snapshotData: Data? = nil
    ) {
        self.result = result
        self.state = state
        self.tick = tick
        self.snapshotData = snapshotData
    }
}

private struct RuntimeSession<State, Action>
where State: GameSimulationBaseState,
      Action: Codable & Equatable & Sendable {
    var validator: GameSimulationProtocolValidator
    var responses: [String: GameSimulationRuntimeResponse<State, Action>] = [:]
    var commandOrder: [String] = []

    mutating func cache(
        _ response: GameSimulationRuntimeResponse<State, Action>,
        commandID: String
    ) {
        guard responses[commandID] == nil else { return }
        responses[commandID] = response
        commandOrder.append(commandID)
        while commandOrder.count > 256 {
            responses[commandOrder.removeFirst()] = nil
        }
    }
}

public actor GameSimulationRuntime<R: GameSimulationReducer & Sendable>
where R.Environment: Sendable {
    public typealias Command = GameSimulationRuntimeCommand<R.Action>
    public typealias CommandEnvelope = GameSimulationCommandEnvelope<Command>
    public typealias Response = GameSimulationRuntimeResponse<R.State, R.Action>

    private var machine: GameSimulationMachine<R>
    private let protocolVersion: Int
    private let maximumMessageBytes: Int
    private let capabilityPolicy: @Sendable (
        GameSimulationHandshake
    ) -> Set<GameSimulationCapability>
    private let commandCapability: @Sendable (Command) -> GameSimulationCapability?
    private var sessions: [GameSimulationSessionID: RuntimeSession<R.State, R.Action>]

    public init(
        machine: sending GameSimulationMachine<R>,
        protocolVersion: Int,
        maximumMessageBytes: Int = 1_048_576,
        capabilityPolicy: @escaping @Sendable (
            GameSimulationHandshake
        ) -> Set<GameSimulationCapability> = { _ in [] },
        commandCapability: @escaping @Sendable (
            Command
        ) -> GameSimulationCapability? = { _ in nil }
    ) {
        self.machine = machine
        self.protocolVersion = protocolVersion
        self.maximumMessageBytes = maximumMessageBytes
        self.capabilityPolicy = capabilityPolicy
        self.commandCapability = commandCapability
        sessions = [:]
    }

    public func connect(
        _ handshake: GameSimulationHandshake
    ) throws -> GameSimulationSessionID {
        var validator = GameSimulationProtocolValidator(
            protocolVersion: protocolVersion,
            maximumMessageBytes: maximumMessageBytes,
            grantedCapabilities: capabilityPolicy(handshake)
        )
        try validator.acceptHandshake(handshake)
        let sessionID = GameSimulationSessionID.random()
        sessions[sessionID] = RuntimeSession(validator: validator)
        return sessionID
    }

    public func disconnect(_ sessionID: GameSimulationSessionID) {
        sessions[sessionID] = nil
    }

    public func submit(
        _ envelope: CommandEnvelope,
        sessionID: GameSimulationSessionID
    ) -> Response {
        guard var session = sessions[sessionID] else {
            return rejection(
                envelope: envelope,
                code: "protocol.invalid-session",
                message: "session is not connected"
            )
        }
        if let cached = session.responses[envelope.commandID] {
            return cached
        }

        do {
            let encodedByteCount = try JSONEncoder().encode(envelope).count
            let requiredCapability = commandCapability(envelope.payload)
                ?? envelope.requiredCapability
            try session.validator.validateCommand(
                requiredCapability: requiredCapability,
                encodedByteCount: encodedByteCount
            )
        } catch let error as GameSimulationProtocolError {
            let response = rejection(
                envelope: envelope,
                code: error.code,
                message: error.code
            )
            session.cache(response, commandID: envelope.commandID)
            sessions[sessionID] = session
            return response
        } catch {
            let response = rejection(
                envelope: envelope,
                code: "command.encoding-failed",
                message: "command encoding failed"
            )
            session.cache(response, commandID: envelope.commandID)
            sessions[sessionID] = session
            return response
        }

        if envelope.payload.requiresExpectedRevision,
           envelope.expectedRevision == nil {
            let response = rejection(
                envelope: envelope,
                code: "command.expected-revision-required",
                message: "mutating commands require expected revision"
            )
            session.cache(response, commandID: envelope.commandID)
            sessions[sessionID] = session
            return response
        }

        if let expectedRevision = envelope.expectedRevision,
           expectedRevision != machine.revision {
            let response = rejection(
                envelope: envelope,
                code: "command.revision-conflict",
                message: "expected revision does not match"
            )
            session.cache(response, commandID: envelope.commandID)
            sessions[sessionID] = session
            return response
        }

        let response: Response
        do {
            var snapshotData: Data?
            switch envelope.payload {
            case .pause:
                if !machine.isPaused {
                    try machine.validateControlMutation()
                    machine.pause()
                    try machine.commitValidatedControlMutation()
                }
            case .resume:
                if machine.isPaused {
                    try machine.validateControlMutation()
                    machine.resume()
                    try machine.commitValidatedControlMutation()
                }
            case .setSpeed(let speed):
                if machine.speed != speed {
                    try machine.validateControlMutation()
                    try machine.setSpeed(speed)
                    try machine.commitValidatedControlMutation()
                }
            case .step(let ticks):
                try machine.step(ticks: ticks)
            case .dispatch(let action):
                try machine.send(action)
            case .requestSnapshot:
                snapshotData = try machine.snapshotData(createdAt: nil)
            }
            response = Response(
                result: .accepted(
                    commandID: envelope.commandID,
                    revision: machine.revision
                ),
                state: machine.state,
                tick: machine.currentTick,
                snapshotData: snapshotData
            )
        } catch let error as GameSimulationExecutionError {
            response = rejection(
                envelope: envelope,
                code: error.code,
                message: error.code
            )
        } catch let error as GameSimulationSnapshotError {
            response = rejection(
                envelope: envelope,
                code: error.code,
                message: error.code
            )
        } catch {
            response = rejection(
                envelope: envelope,
                code: "command.execution-failed",
                message: "command execution failed"
            )
        }

        session.cache(response, commandID: envelope.commandID)
        sessions[sessionID] = session
        return response
    }

    public func currentState() -> R.State {
        machine.state
    }

    public func currentRevision() -> Int64 {
        machine.revision
    }

    public func currentTick() -> GameSimulationTick {
        machine.currentTick
    }

    private func rejection(
        envelope: CommandEnvelope,
        code: String,
        message: String
    ) -> Response {
        Response(
            result: .rejected(
                commandID: envelope.commandID,
                revision: machine.revision,
                code: code,
                message: message
            ),
            state: nil,
            tick: machine.currentTick
        )
    }
}
