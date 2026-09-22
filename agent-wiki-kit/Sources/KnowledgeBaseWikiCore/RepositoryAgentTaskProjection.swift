import Foundation

public struct RepositoryAgentTaskProjection: Codable, Sendable, Equatable {
    public enum State: String, Codable, Sendable {
        case unbound
        case awaitingWorker = "awaiting-worker"
        case executionFailed = "execution-failed"
        case stale
        case awaitingVerification = "awaiting-verification"
        case verified
    }

    public let schemaVersion: String
    public let canonicalTaskId: String
    public let state: State
    public let bindingObjectId: String?
    public let runtimeTaskId: String?
    public let dispatchId: String?
    public let knowledgeObjectIds: [String]
    public let knowledgeSnapshotHash: String?
    public let currentKnowledgeSnapshotHash: String?
    public let sourceCommit: String?
    public let rulesCapsule: [String]
    public let boundAt: Date?
    public let knowledgeCapturedAt: Date?
    public let verificationReceiptObjectId: String?
    public let workerDoneObjectId: String?
    public let workerFailureObjectId: String?
    public let workerFailureExitCode: Int32?
    public let workerFailureMessage: String?
    public let doneObjectId: String?
    public let warnings: [RepositoryAgentTaskWarning]
}
