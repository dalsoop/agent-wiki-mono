import Foundation

public enum GameSimulationClientKind: String, Codable, CaseIterable, Sendable {
    case ui
    case cli
    case agent
    case test
}

public enum GameSimulationCapability: String, Codable, Hashable, Sendable {
    case debug
    case cheat
}

public struct GameSimulationHandshake: Codable, Equatable, Sendable {
    public var protocolVersion: Int
    public var clientKind: GameSimulationClientKind
    public var clientVersion: String

    public init(
        protocolVersion: Int,
        clientKind: GameSimulationClientKind,
        clientVersion: String
    ) {
        self.protocolVersion = protocolVersion
        self.clientKind = clientKind
        self.clientVersion = clientVersion
    }
}
