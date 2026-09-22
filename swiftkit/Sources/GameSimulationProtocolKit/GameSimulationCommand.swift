import Foundation

public struct GameSimulationCommandEnvelope<Payload>: Codable, Equatable, Sendable
where Payload: Codable & Equatable & Sendable {
    public var commandID: String
    public var expectedRevision: Int64?
    public var requiredCapability: GameSimulationCapability?
    public var payload: Payload

    public init(
        commandID: String,
        expectedRevision: Int64? = nil,
        requiredCapability: GameSimulationCapability? = nil,
        payload: Payload
    ) {
        self.commandID = commandID
        self.expectedRevision = expectedRevision
        self.requiredCapability = requiredCapability
        self.payload = payload
    }
}

public enum GameSimulationRuntimeCommand<Action>: Codable, Equatable, Sendable
where Action: Codable & Equatable & Sendable {
    case pause
    case resume
    case setSpeed(Int)
    case step(Int64)
    case dispatch(Action)
    case requestSnapshot

    public var requiresExpectedRevision: Bool {
        switch self {
        case .requestSnapshot:
            false
        case .pause, .resume, .setSpeed, .step, .dispatch:
            true
        }
    }
}

public enum GameSimulationCommandResult: Codable, Equatable, Sendable {
    case accepted(commandID: String, revision: Int64)
    case rejected(
        commandID: String,
        revision: Int64,
        code: String,
        message: String
    )

    public var revision: Int64 {
        switch self {
        case .accepted(_, let revision), .rejected(_, let revision, _, _):
            revision
        }
    }

    public var rejectionCode: String? {
        guard case .rejected(_, _, let code, _) = self else { return nil }
        return code
    }
}
