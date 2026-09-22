import Foundation

public enum GameSimulationEventChannel: String, Codable, Sendable {
    case world
    case direct
}

public enum GameSimulationEventUrgency: String, Codable, Sendable {
    case urgent
    case routine
    case noise
}

public struct GameSimulationEventEnvelope<Payload>: Codable, Equatable, Sendable
where Payload: Codable & Equatable & Sendable {
    public var id: String
    public var revision: Int64
    public var channel: GameSimulationEventChannel
    public var urgency: GameSimulationEventUrgency
    public var coalescingKey: String?
    public var payload: Payload

    public init(
        id: String,
        revision: Int64,
        channel: GameSimulationEventChannel,
        urgency: GameSimulationEventUrgency,
        coalescingKey: String? = nil,
        payload: Payload
    ) {
        self.id = id
        self.revision = revision
        self.channel = channel
        self.urgency = urgency
        self.coalescingKey = coalescingKey
        self.payload = payload
    }
}

public struct GameSimulationRevisionTracker: Equatable, Sendable {
    public private(set) var lastRevision: Int64

    public init(lastRevision: Int64) {
        self.lastRevision = lastRevision
    }

    public mutating func accept(_ revision: Int64) throws {
        guard lastRevision < .max else {
            throw GameSimulationProtocolError.revisionOverflow
        }
        let expected = lastRevision + 1
        guard revision == expected else {
            throw GameSimulationProtocolError.revisionGap(
                expected: expected,
                received: revision
            )
        }
        lastRevision = revision
    }

    public mutating func reset(to revision: Int64) {
        lastRevision = revision
    }
}
