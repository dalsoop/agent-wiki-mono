import Foundation

public enum GameSimulationProtocolError: Error, Equatable, Sendable {
    case handshakeRequired
    case handshakeAlreadyAccepted
    case versionMismatch(expected: Int, received: Int)
    case messageTooLarge(maximum: Int, received: Int)
    case invalidMessageSize(Int)
    case missingCapability(GameSimulationCapability)
    case revisionGap(expected: Int64, received: Int64)
    case revisionOverflow

    public var code: String {
        switch self {
        case .handshakeRequired: "protocol.handshake-required"
        case .handshakeAlreadyAccepted: "protocol.handshake-already-accepted"
        case .versionMismatch: "protocol.version-mismatch"
        case .messageTooLarge: "protocol.message-too-large"
        case .invalidMessageSize: "protocol.invalid-message-size"
        case .missingCapability: "protocol.missing-capability"
        case .revisionGap: "protocol.revision-gap"
        case .revisionOverflow: "protocol.revision-overflow"
        }
    }
}

public struct GameSimulationProtocolValidator: Sendable {
    public let protocolVersion: Int
    public let maximumMessageBytes: Int
    public let grantedCapabilities: Set<GameSimulationCapability>
    public private(set) var handshake: GameSimulationHandshake?

    public init(
        protocolVersion: Int,
        maximumMessageBytes: Int = 1_048_576,
        grantedCapabilities: Set<GameSimulationCapability> = []
    ) {
        self.protocolVersion = protocolVersion
        self.maximumMessageBytes = max(0, maximumMessageBytes)
        self.grantedCapabilities = grantedCapabilities
    }

    public var clientKind: GameSimulationClientKind? {
        handshake?.clientKind
    }

    public mutating func acceptHandshake(
        _ handshake: GameSimulationHandshake
    ) throws {
        guard self.handshake == nil else {
            throw GameSimulationProtocolError.handshakeAlreadyAccepted
        }
        guard handshake.protocolVersion == protocolVersion else {
            throw GameSimulationProtocolError.versionMismatch(
                expected: protocolVersion,
                received: handshake.protocolVersion
            )
        }
        self.handshake = handshake
    }

    public func validateCommand(
        requiredCapability: GameSimulationCapability?,
        encodedByteCount: Int
    ) throws {
        guard handshake != nil else {
            throw GameSimulationProtocolError.handshakeRequired
        }
        guard encodedByteCount >= 0 else {
            throw GameSimulationProtocolError.invalidMessageSize(encodedByteCount)
        }
        guard encodedByteCount <= maximumMessageBytes else {
            throw GameSimulationProtocolError.messageTooLarge(
                maximum: maximumMessageBytes,
                received: encodedByteCount
            )
        }
        if let requiredCapability,
           !grantedCapabilities.contains(requiredCapability) {
            throw GameSimulationProtocolError.missingCapability(requiredCapability)
        }
    }
}
