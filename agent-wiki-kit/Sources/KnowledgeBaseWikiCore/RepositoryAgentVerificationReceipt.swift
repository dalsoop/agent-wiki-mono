import Foundation

public struct RepositoryAgentVerificationReceipt: Codable, Sendable, Equatable {
    public enum Outcome: String, Codable, Sendable { case verified, rejected }

    public static let schemaVersion = "knowledge-base-wiki.repository-agent-verification-receipt.v1"
    public static let objectType = "repository-agent-verification-receipt"

    public let schemaVersion: String
    public let canonicalTaskId: String
    public let runtimeTaskId: String
    public let dispatchId: String
    public let bindingObjectId: String
    public let knowledgeSnapshotHash: String
    public let sourceCommit: String
    public let checker: String
    public let outcome: Outcome
    public let checkedAt: Date

    public struct Draft: Sendable, Equatable {
        public var canonicalTaskId: String
        public var runtimeTaskId: String
        public var dispatchId: String
        public var bindingObjectId: String
        public var knowledgeSnapshotHash: String
        public var sourceCommit: String
        public var checker: String
        public var outcome: Outcome
        public var checkedAt: Date
    }

    public init(_ draft: Draft) throws {
        self.schemaVersion = Self.schemaVersion
        self.canonicalTaskId = draft.canonicalTaskId
        self.runtimeTaskId = draft.runtimeTaskId
        self.dispatchId = draft.dispatchId
        self.bindingObjectId = draft.bindingObjectId
        self.knowledgeSnapshotHash = draft.knowledgeSnapshotHash
        self.sourceCommit = draft.sourceCommit
        self.checker = draft.checker
        self.outcome = draft.outcome
        self.checkedAt = draft.checkedAt
        try validate()
    }

    /// 하위호환 — 축을 직접 나열하는 옛 호출부(wiki CLI `task adapter-check`)도 그대로
    /// 컴파일된다. 새 코드는 `Draft` 를 만들어 `init(_:)` 로 쓴다.
    public init(
        canonicalTaskId: String,
        runtimeTaskId: String,
        dispatchId: String,
        bindingObjectId: String,
        knowledgeSnapshotHash: String,
        sourceCommit: String,
        checker: String,
        outcome: Outcome,
        checkedAt: Date
    ) throws {
        try self.init(Draft(
            canonicalTaskId: canonicalTaskId,
            runtimeTaskId: runtimeTaskId,
            dispatchId: dispatchId,
            bindingObjectId: bindingObjectId,
            knowledgeSnapshotHash: knowledgeSnapshotHash,
            sourceCommit: sourceCommit,
            checker: checker,
            outcome: outcome,
            checkedAt: checkedAt))
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, canonicalTaskId, taskId, runtimeTaskId, dispatchId, bindingObjectId
        case knowledgeSnapshotHash, sourceCommit, checker, outcome, checkedAt
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(canonicalTaskId, forKey: .canonicalTaskId)
        try c.encode(runtimeTaskId, forKey: .runtimeTaskId)
        try c.encode(dispatchId, forKey: .dispatchId)
        try c.encode(bindingObjectId, forKey: .bindingObjectId)
        try c.encode(knowledgeSnapshotHash, forKey: .knowledgeSnapshotHash)
        try c.encode(sourceCommit, forKey: .sourceCommit)
        try c.encode(checker, forKey: .checker)
        try c.encode(outcome, forKey: .outcome)
        try c.encode(checkedAt, forKey: .checkedAt)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let schema = try c.decodeIfPresent(String.self, forKey: .schemaVersion) ?? Self.schemaVersion
        guard schema == Self.schemaVersion else {
            throw RepositoryAgentOrchestrationError.unsupportedSchema(schema)
        }
        self.schemaVersion = schema
        self.canonicalTaskId = try c.decodeIfPresent(String.self, forKey: .canonicalTaskId)
            ?? c.decodeIfPresent(String.self, forKey: .taskId) ?? ""
        self.runtimeTaskId = try c.decodeIfPresent(String.self, forKey: .runtimeTaskId) ?? ""
        self.dispatchId = try c.decodeIfPresent(String.self, forKey: .dispatchId) ?? ""
        self.bindingObjectId = try c.decodeIfPresent(String.self, forKey: .bindingObjectId) ?? ""
        self.knowledgeSnapshotHash = try c.decodeIfPresent(String.self, forKey: .knowledgeSnapshotHash) ?? ""
        self.sourceCommit = try c.decodeIfPresent(String.self, forKey: .sourceCommit) ?? ""
        self.checker = try c.decodeIfPresent(String.self, forKey: .checker) ?? ""
        self.outcome = try c.decodeIfPresent(Outcome.self, forKey: .outcome) ?? .rejected
        self.checkedAt = try c.decodeIfPresent(Date.self, forKey: .checkedAt) ?? .distantPast
        try validate()
    }

    public func validate() throws {
        for (field, value) in [
            ("canonicalTaskId", canonicalTaskId), ("runtimeTaskId", runtimeTaskId), ("dispatchId", dispatchId),
            ("bindingObjectId", bindingObjectId), ("knowledgeSnapshotHash", knowledgeSnapshotHash),
            ("sourceCommit", sourceCommit), ("checker", checker),
        ] where value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw RepositoryAgentOrchestrationError.missingField(field)
        }
    }

    public func json() throws -> String {
        String(decoding: try RepositoryAgentOrchestration.encoder.encode(self), as: UTF8.self)
    }

    public static func decode(body: String) -> Self? {
        guard let data = body.data(using: .utf8) else { return nil }
        return try? RepositoryAgentOrchestration.decoder.decode(Self.self, from: data)
    }

    /// Source compatibility only. New JSON always emits canonicalTaskId.
    public var taskId: String { canonicalTaskId }
}

/// Explicit public adapter input. Producers send JSON via stdin or an explicitly named file;
