import Foundation

public enum ParityOracleError: Error, Equatable, Sendable {
    case invalidJSON
    case isomorphismViolation(ParityVerdict)
}

public struct ParityDiff: Sendable, Equatable, Hashable {
    public enum Kind: String, Sendable, Codable, Equatable, Hashable {
        case missingKeyInGUI
        case missingKeyInCLI
        case typeMismatch
        case valueMismatch
        case arrayLengthMismatch
    }

    public let path: String
    public let kind: Kind
    public let cliValue: String?
    public let guiValue: String?
    public let message: String

    public init(
        path: String,
        kind: Kind,
        cliValue: String? = nil,
        guiValue: String? = nil,
        message: String
    ) {
        self.path = path
        self.kind = kind
        self.cliValue = cliValue
        self.guiValue = guiValue
        self.message = message
    }
}

public struct ParityVerdict: Sendable, Equatable, Hashable {
    public let isIsomorphic: Bool
    public let differences: [ParityDiff]
    public let comparedNodesCount: Int

    public init(
        isIsomorphic: Bool,
        differences: [ParityDiff] = [],
        comparedNodesCount: Int = 0
    ) {
        self.isIsomorphic = isIsomorphic
        self.differences = differences
        self.comparedNodesCount = comparedNodesCount
    }
}
