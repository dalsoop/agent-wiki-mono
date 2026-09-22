import Foundation

public enum ArchitectureEdgeType: String, Codable, Sendable, CaseIterable {
    case dependsOn
    case invokesProcess
    case emitsState
    case readsStateMirror
    case attachesSkill
    case bridgesMCP
}

public enum ContractKind: String, Codable, Sendable, CaseIterable {
    case directImport
    case cliFlag
    case ipc
    case stateMirrorFile
    case launchServices
    case mcpProtocol
}

public enum ContractRiskLevel: String, Codable, Sendable {
    case safe
    case warning
    case criticalViolation
}

public struct EdgeContract: Codable, Sendable, Equatable {
    public var kind: ContractKind
    public var detail: String?
    public var isProcessCompliant: Bool
    public var riskLevel: ContractRiskLevel

    public init(
        kind: ContractKind,
        detail: String? = nil,
        isProcessCompliant: Bool = true,
        riskLevel: ContractRiskLevel = .safe
    ) {
        self.kind = kind
        self.detail = detail
        self.isProcessCompliant = isProcessCompliant
        self.riskLevel = riskLevel
    }
}

public struct ArchitectureEdge: Codable, Sendable, Equatable, Identifiable {
    public var id: String { "\(source)->\(target):\(type.rawValue)" }
    public var source: String
    public var target: String
    public var type: ArchitectureEdgeType
    public var contract: EdgeContract
    public var evidence: SourceEvidence?

    public init(
        source: String,
        target: String,
        type: ArchitectureEdgeType,
        contract: EdgeContract,
        evidence: SourceEvidence? = nil
    ) {
        self.source = source
        self.target = target
        self.type = type
        self.contract = contract
        self.evidence = evidence
    }
}
