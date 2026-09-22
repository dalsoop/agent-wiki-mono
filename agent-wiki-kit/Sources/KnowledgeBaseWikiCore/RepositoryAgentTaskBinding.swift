import Foundation

public struct RepositoryAgentTaskBinding: Codable, Sendable, Equatable {
    public static let schemaVersion = "knowledge-base-wiki.repository-agent-task-binding.v1"
    public static let objectType = "repository-agent-task-binding"
    public static let maxKnowledgeObjectCount = 32
    public static let maxRuleCount = 8
    public static let legacyMaxRuleCount = 16
    public static let maxRuleUTF8Bytes = 512
    public static let maxRulesCapsuleUTF8Bytes = 4_096

    public let schemaVersion: String
    public let canonicalTaskId: String
    public let runtimeTaskId: String
    public let dispatchId: String
    public let knowledgeObjectIds: [String]
    public let knowledgeSnapshotHash: String
    public let sourceCommit: String
    public let rulesCapsule: [String]
    public let boundAt: Date
    public let knowledgeCapturedAt: Date

    public struct Draft: Sendable, Equatable {
        public var canonicalTaskId: String
        public var runtimeTaskId: String
        public var dispatchId: String
        public var knowledgeObjectIds: [String]
        public var knowledgeSnapshotHash: String
        public var sourceCommit: String
        public var rulesCapsule: [String]
        public var boundAt: Date
        public var knowledgeCapturedAt: Date
    }

    public init(_ draft: Draft) throws {
        self.schemaVersion = Self.schemaVersion
        self.canonicalTaskId = draft.canonicalTaskId
        self.runtimeTaskId = draft.runtimeTaskId
        self.dispatchId = draft.dispatchId
        self.knowledgeObjectIds = Array(Set(draft.knowledgeObjectIds)).sorted()
        self.knowledgeSnapshotHash = draft.knowledgeSnapshotHash
        self.sourceCommit = draft.sourceCommit
        self.rulesCapsule = draft.rulesCapsule
        self.boundAt = draft.boundAt
        self.knowledgeCapturedAt = draft.knowledgeCapturedAt
        try validate()
    }

    /// 하위호환 — 축을 직접 나열하는 옛 호출부(wiki CLI `task adapter`)도 그대로
    /// 컴파일된다. 새 코드는 `Draft` 를 만들어 `init(_:)` 로 쓴다.
    public init(
        canonicalTaskId: String,
        runtimeTaskId: String,
        dispatchId: String,
        knowledgeObjectIds: [String],
        knowledgeSnapshotHash: String,
        sourceCommit: String,
        rulesCapsule: [String],
        boundAt: Date,
        knowledgeCapturedAt: Date
    ) throws {
        try self.init(Draft(
            canonicalTaskId: canonicalTaskId,
            runtimeTaskId: runtimeTaskId,
            dispatchId: dispatchId,
            knowledgeObjectIds: knowledgeObjectIds,
            knowledgeSnapshotHash: knowledgeSnapshotHash,
            sourceCommit: sourceCommit,
            rulesCapsule: rulesCapsule,
            boundAt: boundAt,
            knowledgeCapturedAt: knowledgeCapturedAt))
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, canonicalTaskId, taskId, runtimeTaskId, dispatchId, knowledgeObjectIds
        case knowledgeSnapshotHash, sourceCommit, rulesCapsule, boundAt, knowledgeCapturedAt
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(canonicalTaskId, forKey: .canonicalTaskId)
        try c.encode(runtimeTaskId, forKey: .runtimeTaskId)
        try c.encode(dispatchId, forKey: .dispatchId)
        try c.encode(knowledgeObjectIds, forKey: .knowledgeObjectIds)
        try c.encode(knowledgeSnapshotHash, forKey: .knowledgeSnapshotHash)
        try c.encode(sourceCommit, forKey: .sourceCommit)
        try c.encode(rulesCapsule, forKey: .rulesCapsule)
        try c.encode(boundAt, forKey: .boundAt)
        try c.encode(knowledgeCapturedAt, forKey: .knowledgeCapturedAt)
    }

    /// Additive/migration-safe parser: v1의 초기 producer가 생략한 capsule/capturedAt은
    /// 빈 capsule/boundAt으로 보완하고, unknown JSON keys는 Codable 기본 동작으로 무시한다.
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
        self.knowledgeObjectIds = Array(Set(
            try c.decodeIfPresent([String].self, forKey: .knowledgeObjectIds) ?? []
        )).sorted()
        self.knowledgeSnapshotHash = try c.decodeIfPresent(String.self, forKey: .knowledgeSnapshotHash) ?? ""
        self.sourceCommit = try c.decodeIfPresent(String.self, forKey: .sourceCommit) ?? ""
        self.rulesCapsule = try c.decodeIfPresent([String].self, forKey: .rulesCapsule) ?? []
        self.boundAt = try c.decodeIfPresent(Date.self, forKey: .boundAt) ?? .distantPast
        self.knowledgeCapturedAt = try c.decodeIfPresent(Date.self, forKey: .knowledgeCapturedAt) ?? boundAt
        try validate(maxRules: Self.legacyMaxRuleCount)
    }

    public func validate() throws { try validate(maxRules: Self.maxRuleCount) }

    private func validate(maxRules: Int) throws {
        for (field, value) in [
            ("canonicalTaskId", canonicalTaskId), ("runtimeTaskId", runtimeTaskId), ("dispatchId", dispatchId),
            ("knowledgeSnapshotHash", knowledgeSnapshotHash), ("sourceCommit", sourceCommit),
        ] where value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw RepositoryAgentOrchestrationError.missingField(field)
        }
        guard knowledgeObjectIds.count <= Self.maxKnowledgeObjectCount else {
            throw RepositoryAgentOrchestrationError.tooManyKnowledgeObjects(knowledgeObjectIds.count)
        }
        guard rulesCapsule.count <= maxRules else {
            throw RepositoryAgentOrchestrationError.tooManyRules(rulesCapsule.count)
        }
        for rule in rulesCapsule {
            let bytes = rule.lengthOfBytes(using: .utf8)
            guard bytes <= Self.maxRuleUTF8Bytes else {
                throw RepositoryAgentOrchestrationError.ruleTooLarge(bytes)
            }
        }
        let totalBytes = rulesCapsule.reduce(0) { $0 + $1.lengthOfBytes(using: .utf8) }
        guard totalBytes <= Self.maxRulesCapsuleUTF8Bytes else {
            throw RepositoryAgentOrchestrationError.capsuleTooLarge(totalBytes)
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
