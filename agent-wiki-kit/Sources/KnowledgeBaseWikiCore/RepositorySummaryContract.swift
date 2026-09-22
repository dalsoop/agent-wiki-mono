import Foundation

public struct RepositoryTaskItem: Codable, Sendable, Equatable, Identifiable {
    public enum Status: String, Codable, Sendable {
        case open
        case delegated
        case completed
    }

    public let taskId: String
    public let title: String
    public let status: Status
    public let assignee: String?
    public let author: String
    public let createdAt: Date
    public let updatedAt: Date
    public let orchestration: RepositoryAgentTaskProjection

    public var id: String { taskId }
}

public struct RepositoryTaskSummary: Codable, Sendable, Equatable {
    public let total: Int
    public let open: Int
    public let delegated: Int
    public let completed: Int
    public let items: [RepositoryTaskItem]

    public init(total: Int, open: Int, delegated: Int, completed: Int, items: [RepositoryTaskItem]) {
        self.total = total
        self.open = open
        self.delegated = delegated
        self.completed = completed
        self.items = items
    }
}

public struct RepositoryTaskListContract: Codable, Sendable, Equatable {
    public static let schemaVersion = "knowledge-base-wiki.task-list.v1"

    public let schemaVersion: String
    public let generatedAt: Date
    public let repoId: String?
    public let sourceUpdatedAt: Date?
    public let summary: RepositoryTaskSummary

    public init(
        graph: LedgerTaskGraph,
        repoId: String? = nil,
        generatedAt: Date = Date()
    ) {
        self.schemaVersion = Self.schemaVersion
        self.generatedAt = generatedAt
        self.repoId = repoId
        self.sourceUpdatedAt = graph.items.map(\.updatedAt).max()
        self.summary = RepositoryTaskSummary(
            total: graph.items.count,
            open: graph.items.filter { $0.status == .open }.count,
            delegated: graph.items.filter { $0.status == .delegated }.count,
            completed: graph.items.filter { $0.status == .completed }.count,
            items: graph.items)
    }
}

public struct RepositoryKnowledgeBrief: Codable, Sendable, Equatable {
    public struct Item: Codable, Sendable, Equatable, Identifiable {
        public let objectId: String
        public let title: String
        public let type: String?
        public let updatedAt: Date
        public var id: String { objectId }
    }

    public let objectCount: Int
    public let headCount: Int
    public let recent: [Item]
}

public struct RepositoryProvenanceHealth: Codable, Sendable, Equatable {
    public enum Status: String, Codable, Sendable { case healthy, issues }

    public let status: Status
    public let violationCount: Int
    public let promotionReceiptCount: Int
    public let issues: [String]
}

public struct RepositorySummaryRepository: Codable, Sendable, Equatable {
    public let id: String
    public let displayName: String
    public let rootPath: String
    public let remote: String
    public let defaultBranch: String
    public let worktreePath: String
    public let branch: String
    /// Additive provenance field; ACP may ignore it while retaining v1 compatibility.
    public let sourceCommit: String
}

public struct RepositoryKnowledgeSummary: Codable, Sendable, Equatable {
    public let total: Int
    public let recentDecisions: [RepositoryKnowledgeBrief.Item]
}

public struct RepositoryPromotionSummary: Codable, Sendable, Equatable {
    public let candidates: Int
    public let pending: Int
    public let promoted: Int
}

public struct RepositoryIntegritySummary: Codable, Sendable, Equatable {
    public let status: RepositoryProvenanceHealth.Status
    public let issues: [String]
}

/// Subset intentionally shaped for StateMirror consumers. The GUI can publish this payload
/// without reimplementing repository identity or task/provenance derivation.
public struct RepositoryStateMirrorHook: Codable, Sendable, Equatable {
    public let orchestrationAdapterSchemaVersion: String
    public let orchestrationCapsuleSchemaVersion: String
    public let currentRepository: String
    public let repoId: String
    public let normalizedRemote: String
    public let worktreePath: String
    public let branch: String
    public let sourceCommit: String
    public let taskOpenCount: Int
    public let taskCompletedCount: Int
    public let taskUnboundCount: Int
    public let taskAwaitingWorkerCount: Int
    public let taskExecutionFailedCount: Int
    public let taskStaleCount: Int
    public let taskAwaitingVerificationCount: Int
    public let taskVerifiedCount: Int
    public let taskWorkerDoneAwaitingCount: Int
    public let taskStates: [RepositoryTaskItem]
    public let provenanceIssueCount: Int
    public let sourceUpdatedAt: Date
}

/// Versioned, read-only contract consumed by execution/control-plane clients.
public struct RepositorySummaryContract: Codable, Sendable, Equatable {
    public static let schemaVersion = "knowledge-base-wiki.repository-summary.v1"

    public let schemaVersion: String
    public let generatedAt: Date
    public let sourceUpdatedAt: Date
    public let repository: RepositorySummaryRepository
    public let tasks: RepositoryTaskSummary
    public let knowledge: RepositoryKnowledgeSummary
    public let promotion: RepositoryPromotionSummary
    public let integrity: RepositoryIntegritySummary
    public let stateMirror: RepositoryStateMirrorHook

    public init(
        identity: RepositoryIdentity,
        store: LedgerStore,
        peerWorlds: [LedgerWorld] = [],
        generatedAt: Date = Date(),
        recentLimit: Int = 10
    ) {
        let objects = store.scan()
        let heads = store.heads(objects)
        let graph = LedgerTaskGraph(objects: objects, currentSourceCommit: identity.sourceCommit)
        let taskList = RepositoryTaskListContract(
            graph: graph, repoId: identity.repoId, generatedAt: generatedAt)
        let knowledgeHeads = heads.filter {
            !["task", "handoff", "done", "promotion-receipt", "promotion-link"]
                .contains($0.effectiveType ?? "") && !$0.isProcess
        }
        let recentDecisions = knowledgeHeads
            .filter { $0.effectiveType == "decision" }
            .sorted { ($0.published, $0.id) > ($1.published, $1.id) }
            .prefix(max(0, recentLimit))
            .map { RepositoryKnowledgeBrief.Item(
                objectId: $0.id,
                title: $0.title ?? "(제목 없음)",
                type: $0.effectiveType,
                updatedAt: $0.published) }
        var violations = store.verify()
        violations.append(contentsOf: PromotionVerifier.verify(
            store: store, peerWorlds: peerWorlds, currentRepository: identity))
        let issues = violations.map { "\($0.id): \($0.problem)" }.sorted()
        let receipts = objects.compactMap { object -> PromotionReceipt? in
            guard object.effectiveType == "promotion-receipt" else { return nil }
            return PromotionReceipt.decode(body: object.body)
        }
        let promotedSourceIDs = Set(receipts.map(\.sourceObjectId))
        let candidateCount = knowledgeHeads.filter {
            $0.tags.contains("promotion-candidate") && !promotedSourceIDs.contains($0.id)
        }.count
        let promotionIssueCount = violations.filter { $0.problem.contains("promotion") }.count
        // An empty repository still has a fresh observable snapshot; generatedAt is the
        // source timestamp until the first append-only object establishes ledger freshness.
        let sourceUpdatedAt = objects.map(\.published).max() ?? generatedAt
        let provenance = RepositoryProvenanceHealth(
            status: issues.isEmpty ? .healthy : .issues,
            violationCount: issues.count,
            promotionReceiptCount: receipts.count,
            issues: issues)
        let hook = RepositoryStateMirrorHook(
            orchestrationAdapterSchemaVersion: RepositoryAgentAdapterEvent.schemaVersion,
            orchestrationCapsuleSchemaVersion: RepositoryAgentCapsule.schemaVersion,
            currentRepository: identity.repoId,
            repoId: identity.repoId,
            normalizedRemote: identity.normalizedRemote,
            worktreePath: identity.worktreePath,
            branch: identity.currentBranch ?? "",
            sourceCommit: identity.sourceCommit,
            taskOpenCount: taskList.summary.open + taskList.summary.delegated,
            taskCompletedCount: taskList.summary.completed,
            taskUnboundCount: taskList.summary.items.filter { $0.orchestration.state == .unbound }.count,
            taskAwaitingWorkerCount: taskList.summary.items.filter { $0.orchestration.state == .awaitingWorker }.count,
            taskExecutionFailedCount: taskList.summary.items.filter { $0.orchestration.state == .executionFailed }.count,
            taskStaleCount: taskList.summary.items.filter { $0.orchestration.state == .stale }.count,
            taskAwaitingVerificationCount: taskList.summary.items.filter { $0.orchestration.state == .awaitingVerification }.count,
            taskVerifiedCount: taskList.summary.items.filter { $0.orchestration.state == .verified }.count,
            taskWorkerDoneAwaitingCount: taskList.summary.items.filter {
                $0.orchestration.state == .awaitingVerification
                    && $0.orchestration.workerDoneObjectId != nil
            }.count,
            taskStates: taskList.summary.items,
            provenanceIssueCount: issues.count,
            sourceUpdatedAt: sourceUpdatedAt)

        self.schemaVersion = Self.schemaVersion
        self.generatedAt = generatedAt
        self.sourceUpdatedAt = sourceUpdatedAt
        let remoteTail = identity.normalizedRemote.split(separator: "/").last.map(String.init)
            ?? URL(fileURLWithPath: identity.worktreePath).lastPathComponent
        self.repository = RepositorySummaryRepository(
            id: identity.repoId,
            displayName: remoteTail,
            rootPath: identity.worktreePath,
            remote: identity.normalizedRemote,
            defaultBranch: identity.defaultBranch ?? "",
            worktreePath: identity.worktreePath,
            branch: identity.currentBranch ?? "",
            sourceCommit: identity.sourceCommit)
        self.tasks = taskList.summary
        self.knowledge = RepositoryKnowledgeSummary(
            total: knowledgeHeads.count,
            recentDecisions: Array(recentDecisions))
        self.promotion = RepositoryPromotionSummary(
            candidates: candidateCount,
            pending: promotionIssueCount,
            promoted: promotedSourceIDs.count)
        self.integrity = RepositoryIntegritySummary(status: provenance.status, issues: issues)
        self.stateMirror = hook
    }
}
