import Foundation

public struct RepositoryAgentCapsule: Codable, Sendable, Equatable {
    public static let schemaVersion = "knowledge-base-wiki.repository-agent-capsule.v1"

    public let schemaVersion: String
    public let canonicalTaskId: String
    public let runtimeTaskId: String?
    public let dispatchId: String?
    public let bindingObjectId: String?
    public let workerDoneObjectId: String?
    public let workerFailureObjectId: String?
    public let workerFailureExitCode: Int32?
    public let workerFailureMessage: String?
    public let knowledgeObjectIds: [String]
    public let knowledgeSnapshotHash: String?
    public let sourceCommit: String?
    public let rulesCapsule: [String]
    public let capturedAt: Date?
    public let gateState: RepositoryAgentTaskProjection.State
    public let stale: Bool
    public let warnings: [RepositoryAgentTaskWarning]

    public init(canonicalTaskId: String, projection: RepositoryAgentTaskProjection) {
        self.schemaVersion = Self.schemaVersion
        self.canonicalTaskId = canonicalTaskId
        self.runtimeTaskId = projection.runtimeTaskId
        self.dispatchId = projection.dispatchId
        self.bindingObjectId = projection.bindingObjectId
        self.workerDoneObjectId = projection.workerDoneObjectId
        self.workerFailureObjectId = projection.workerFailureObjectId
        self.workerFailureExitCode = projection.workerFailureExitCode
        self.workerFailureMessage = projection.workerFailureMessage
        self.knowledgeObjectIds = projection.knowledgeObjectIds
        self.knowledgeSnapshotHash = projection.knowledgeSnapshotHash
        self.sourceCommit = projection.sourceCommit
        self.rulesCapsule = Array(projection.rulesCapsule.prefix(RepositoryAgentTaskBinding.maxRuleCount))
        self.capturedAt = projection.knowledgeCapturedAt
        self.gateState = projection.state
        self.stale = projection.state == .stale
        self.warnings = projection.warnings
    }
}

public struct RepositoryAgentTaskWarning: Codable, Sendable, Equatable, Identifiable {
    public enum Code: String, Codable, Sendable {
        case malformedBinding
        case completionWithoutVerification
        case sourceCommitStale
        case knowledgeSnapshotMismatch
        case knowledgeSuperseded
        case verificationRejected
        case verificationMismatch
    }

    public let code: Code
    public let message: String
    public let objectId: String?
    public let supersededByObjectId: String?

    public var id: String {
        [code.rawValue, objectId ?? "", supersededByObjectId ?? ""].joined(separator: ":")
    }
}
