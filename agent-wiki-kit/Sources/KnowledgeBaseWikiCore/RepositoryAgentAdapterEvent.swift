import Foundation

public struct RepositoryAgentAdapterEvent: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable {
        case task
        case dispatch
        case workerDone = "worker_done"
        case checker
    }

    public static let schemaVersion = "knowledge-base-wiki.repository-agent-adapter-event.v1"
    public static let maxResultUTF8Bytes = 16_384

    public let schemaVersion: String
    public let event: Kind
    public let canonicalTaskId: String
    public let runtimeTaskId: String
    public let dispatchId: String
    public let knowledgeObjectIds: [String]
    public let knowledgeSnapshotHash: String?
    public let sourceCommit: String?
    public let rulesCapsule: [String]
    public let worker: String?
    public let result: String?
    public let checker: String?
    public let outcome: RepositoryAgentVerificationReceipt.Outcome?
    public let bindingObjectId: String?
    public let occurredAt: Date

    public struct Draft: Sendable, Equatable {
        public var event: Kind
        public var canonicalTaskId: String
        public var runtimeTaskId: String
        public var dispatchId: String
        public var knowledgeObjectIds: [String] = []
        public var knowledgeSnapshotHash: String? = nil
        public var sourceCommit: String? = nil
        public var rulesCapsule: [String] = []
        public var worker: String? = nil
        public var result: String? = nil
        public var checker: String? = nil
        public var outcome: RepositoryAgentVerificationReceipt.Outcome? = nil
        public var bindingObjectId: String? = nil
        public var occurredAt: Date
    }

    public init(_ draft: Draft) throws {
        self.schemaVersion = Self.schemaVersion
        self.event = draft.event
        self.canonicalTaskId = draft.canonicalTaskId
        self.runtimeTaskId = draft.runtimeTaskId
        self.dispatchId = draft.dispatchId
        self.knowledgeObjectIds = Array(Set(draft.knowledgeObjectIds)).sorted()
        self.knowledgeSnapshotHash = draft.knowledgeSnapshotHash
        self.sourceCommit = draft.sourceCommit
        self.rulesCapsule = draft.rulesCapsule
        self.worker = draft.worker
        self.result = draft.result
        self.checker = draft.checker
        self.outcome = draft.outcome
        self.bindingObjectId = draft.bindingObjectId
        self.occurredAt = draft.occurredAt
        try validate()
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, event, type, canonicalTaskId, taskId, runtimeTaskId, dispatchId
        case knowledgeObjectIds, knowledgeSnapshotHash, sourceCommit, rulesCapsule
        case worker, result, body, checker, outcome, bindingObjectId, occurredAt
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(event, forKey: .event)
        try c.encode(canonicalTaskId, forKey: .canonicalTaskId)
        try c.encode(runtimeTaskId, forKey: .runtimeTaskId)
        try c.encode(dispatchId, forKey: .dispatchId)
        try c.encode(knowledgeObjectIds, forKey: .knowledgeObjectIds)
        try c.encodeIfPresent(knowledgeSnapshotHash, forKey: .knowledgeSnapshotHash)
        try c.encodeIfPresent(sourceCommit, forKey: .sourceCommit)
        try c.encode(rulesCapsule, forKey: .rulesCapsule)
        try c.encodeIfPresent(worker, forKey: .worker)
        try c.encodeIfPresent(result, forKey: .result)
        try c.encodeIfPresent(checker, forKey: .checker)
        try c.encodeIfPresent(outcome, forKey: .outcome)
        try c.encodeIfPresent(bindingObjectId, forKey: .bindingObjectId)
        try c.encode(occurredAt, forKey: .occurredAt)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let schema = try c.decodeIfPresent(String.self, forKey: .schemaVersion) ?? Self.schemaVersion
        guard schema == Self.schemaVersion else {
            throw RepositoryAgentOrchestrationError.unsupportedSchema(schema)
        }
        self.schemaVersion = schema
        self.event = try c.decodeIfPresent(Kind.self, forKey: .event)
            ?? c.decode(Kind.self, forKey: .type)
        self.canonicalTaskId = try c.decodeIfPresent(String.self, forKey: .canonicalTaskId)
            ?? c.decodeIfPresent(String.self, forKey: .taskId) ?? ""
        self.runtimeTaskId = try c.decodeIfPresent(String.self, forKey: .runtimeTaskId) ?? ""
        self.dispatchId = try c.decodeIfPresent(String.self, forKey: .dispatchId) ?? ""
        self.knowledgeObjectIds = Array(Set(
            try c.decodeIfPresent([String].self, forKey: .knowledgeObjectIds) ?? []
        )).sorted()
        self.knowledgeSnapshotHash = try c.decodeIfPresent(String.self, forKey: .knowledgeSnapshotHash)
        self.sourceCommit = try c.decodeIfPresent(String.self, forKey: .sourceCommit)
        self.rulesCapsule = try c.decodeIfPresent([String].self, forKey: .rulesCapsule) ?? []
        self.worker = try c.decodeIfPresent(String.self, forKey: .worker)
        self.result = try c.decodeIfPresent(String.self, forKey: .result)
            ?? c.decodeIfPresent(String.self, forKey: .body)
        self.checker = try c.decodeIfPresent(String.self, forKey: .checker)
        self.outcome = try c.decodeIfPresent(RepositoryAgentVerificationReceipt.Outcome.self, forKey: .outcome)
        self.bindingObjectId = try c.decodeIfPresent(String.self, forKey: .bindingObjectId)
        self.occurredAt = try c.decodeIfPresent(Date.self, forKey: .occurredAt) ?? .distantPast
        try validate()
    }

    public func validate() throws {
        for (field, value) in [
            ("canonicalTaskId", canonicalTaskId), ("runtimeTaskId", runtimeTaskId), ("dispatchId", dispatchId),
        ] where value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw RepositoryAgentOrchestrationError.missingField(field)
        }
        guard occurredAt != .distantPast else {
            throw RepositoryAgentOrchestrationError.missingField("occurredAt")
        }
        guard knowledgeObjectIds.count <= RepositoryAgentTaskBinding.maxKnowledgeObjectCount else {
            throw RepositoryAgentOrchestrationError.tooManyKnowledgeObjects(knowledgeObjectIds.count)
        }
        guard rulesCapsule.count <= RepositoryAgentTaskBinding.maxRuleCount else {
            throw RepositoryAgentOrchestrationError.tooManyRules(rulesCapsule.count)
        }
        for rule in rulesCapsule {
            let bytes = rule.lengthOfBytes(using: .utf8)
            guard bytes <= RepositoryAgentTaskBinding.maxRuleUTF8Bytes else {
                throw RepositoryAgentOrchestrationError.ruleTooLarge(bytes)
            }
        }
        guard rulesCapsule.reduce(0, { $0 + $1.lengthOfBytes(using: .utf8) })
                <= RepositoryAgentTaskBinding.maxRulesCapsuleUTF8Bytes else {
            throw RepositoryAgentOrchestrationError.capsuleTooLarge(
                rulesCapsule.reduce(0, { $0 + $1.lengthOfBytes(using: .utf8) }))
        }
        if let result, result.lengthOfBytes(using: .utf8) > Self.maxResultUTF8Bytes {
            throw RepositoryAgentOrchestrationError.invalidEvent("result exceeds \(Self.maxResultUTF8Bytes) UTF-8 bytes")
        }
        switch event {
        case .task, .dispatch:
            guard let sourceCommit, !sourceCommit.isEmpty else {
                throw RepositoryAgentOrchestrationError.missingField("sourceCommit")
            }
        case .workerDone:
            guard let worker, !worker.isEmpty else {
                throw RepositoryAgentOrchestrationError.missingField("worker")
            }
        case .checker:
            guard let checker, !checker.isEmpty else {
                throw RepositoryAgentOrchestrationError.missingField("checker")
            }
            guard outcome != nil else { throw RepositoryAgentOrchestrationError.missingField("outcome") }
        }
    }

    public static func decode(data: Data) throws -> Self {
        try RepositoryAgentOrchestration.decoder.decode(Self.self, from: data)
    }
}
