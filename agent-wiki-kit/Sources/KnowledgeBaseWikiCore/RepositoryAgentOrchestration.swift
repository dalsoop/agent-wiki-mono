import CryptoKit
import Foundation

public enum RepositoryAgentOrchestrationError: Error, CustomStringConvertible, Equatable {
    case missingField(String)
    case tooManyKnowledgeObjects(Int)
    case tooManyRules(Int)
    case ruleTooLarge(Int)
    case capsuleTooLarge(Int)
    case unsupportedSchema(String)
    case invalidEvent(String)
    case completionGateDenied(String)

    public var description: String {
        switch self {
        case .missingField(let field): "필수 orchestration 필드 누락: \(field)"
        case .tooManyKnowledgeObjects(let count): "knowledgeObjectIds 한도 초과: \(count)"
        case .tooManyRules(let count): "rules capsule 항목 한도 초과: \(count)"
        case .ruleTooLarge(let bytes): "rules capsule 단일 항목 한도 초과: \(bytes) bytes"
        case .capsuleTooLarge(let bytes): "rules capsule 전체 한도 초과: \(bytes) bytes"
        case .unsupportedSchema(let schema): "지원하지 않는 orchestration schema: \(schema)"
        case .invalidEvent(let reason): "유효하지 않은 orchestration adapter event: \(reason)"
        case .completionGateDenied(let reason): "task 완료 gate 거부: \(reason)"
        }
    }
}

public enum RepositoryAgentOrchestration {
    public static let projectionSchemaVersion = "knowledge-base-wiki.repository-agent-task-state.v1"
    public static let bindsRelation = "binds-runtime"
    public static let contextRelation = "knowledge-context"
    public static let verifiesRelation = "verifies-task"
    public static let verifiesBindingRelation = "verifies-binding"
    public static let verifiedByRelation = "verified-by"
    public static let reportsWorkerDoneRelation = "reports-worker-done"
    public static let reportsWorkerFailureRelation = "reports-worker-failure"
    public static let reportsBindingRelation = "reports-binding"

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// Snapshot includes requested immutable IDs and their current lineage heads. A new
    /// superseding object deterministically changes the hash without modifying old objects.
    public static func knowledgeSnapshotHash(
        knowledgeObjectIds: [String],
        objects: [LedgerObject]
    ) -> String {
        let records = Array(Set(knowledgeObjectIds)).sorted().map { id -> String in
            guard let original = objects.first(where: { $0.id == id }) else { return "\(id):missing" }
            let head = lineageHead(startingAt: original, objects: objects)
            return "\(id):\(head.id):\(head.contentID())"
        }
        return SHA256.hash(data: Data(records.joined(separator: "\n").utf8))
            .map { String(format: "%02x", $0) }.joined()
    }

    public static func activeBinding(
        canonicalTaskId: String,
        objects: [LedgerObject]
    ) -> (object: LedgerObject, binding: RepositoryAgentTaskBinding)? {
        let ordered = objects.sorted { ($0.published, $0.id) < ($1.published, $1.id) }
        let candidates = ordered.filter {
            $0.effectiveType == RepositoryAgentTaskBinding.objectType
                && $0.cites.contains { $0.id == canonicalTaskId && $0.rel == bindsRelation }
        }
        let superseded = Set(candidates.compactMap(\.supersedes))
        let decoded = candidates.compactMap { object -> (LedgerObject, RepositoryAgentTaskBinding)? in
            guard let binding = RepositoryAgentTaskBinding.decode(body: object.body),
                  binding.canonicalTaskId == canonicalTaskId else { return nil }
            return (object, binding)
        }
        return decoded.filter { !superseded.contains($0.0.id) }.last ?? decoded.last
    }

    /// Fail-closed preflight used by every writer of a `done` object.
    @discardableResult
    public static func validateCompletion(
        task: LedgerObject,
        receiptObjectId: String,
        objects: [LedgerObject],
        currentSourceCommit: String? = nil
    ) throws -> LedgerObject {
        guard let (bindingObject, binding) = activeBinding(
            canonicalTaskId: task.id, objects: objects) else {
            throw RepositoryAgentOrchestrationError.completionGateDenied("active binding 없음")
        }
        let state = projection(
            task: task, objects: objects, currentSourceCommit: currentSourceCommit)
        guard state.state != .stale else {
            throw RepositoryAgentOrchestrationError.completionGateDenied("binding context가 stale 상태")
        }
        guard let receiptObject = objects.first(where: { $0.id == receiptObjectId }),
              receiptObject.effectiveType == RepositoryAgentVerificationReceipt.objectType,
              let receipt = RepositoryAgentVerificationReceipt.decode(body: receiptObject.body)
        else { throw RepositoryAgentOrchestrationError.completionGateDenied("verification receipt 없음") }
        let matches = receipt.canonicalTaskId == task.id
            && receipt.runtimeTaskId == binding.runtimeTaskId
            && receipt.dispatchId == binding.dispatchId
            && receipt.bindingObjectId == bindingObject.id
            && receipt.knowledgeSnapshotHash == binding.knowledgeSnapshotHash
            && receipt.sourceCommit == binding.sourceCommit
            && receipt.outcome == .verified
            && receiptObject.cites.contains { $0.id == task.id && $0.rel == verifiesRelation }
            && receiptObject.cites.contains { $0.id == bindingObject.id && $0.rel == verifiesBindingRelation }
        guard matches else {
            throw RepositoryAgentOrchestrationError.completionGateDenied(
                "verified receipt identity/context 불일치")
        }
        return receiptObject
    }

    static func sorted(
        _ warnings: [RepositoryAgentTaskWarning]
    ) -> [RepositoryAgentTaskWarning] {
        warnings.sorted {
            ($0.code.rawValue, $0.objectId ?? "", $0.supersededByObjectId ?? "")
                < ($1.code.rawValue, $1.objectId ?? "", $1.supersededByObjectId ?? "")
        }
    }
}
