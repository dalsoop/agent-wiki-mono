import Foundation
import KnowledgeBaseWikiCore

extension LedgerModel {
    var repositoryIdentity: RepositoryIdentity? {
        get { repo.identity }
        set { repo.identity = newValue }
    }
    var repositorySummary: RepositorySummaryContract? {
        get { repo.summary }
        set { repo.summary = newValue }
    }
    var worldPickerItems: [WorldPickerItem] {
        get { repo.worldPickerItems }
        set { repo.worldPickerItems = newValue }
    }
    var promotionPreview: PromotionPreview? {
        get { repo.promotionPreview }
        set { repo.promotionPreview = newValue }
    }
    var promotionResult: PromotionResult? {
        get { repo.promotionResult }
        set { repo.promotionResult = newValue }
    }
    var promotionMessage: String? {
        get { repo.promotionMessage }
        set { repo.promotionMessage = newValue }
    }
    var promotionMessageIsError: Bool {
        get { repo.promotionMessageIsError }
        set { repo.promotionMessageIsError = newValue }
    }
    var repositoryActionMessage: String? {
        get { repo.actionMessage }
        set { repo.actionMessage = newValue }
    }
    var repositoryActionIsError: Bool {
        get { repo.actionIsError }
        set { repo.actionIsError = newValue }
    }
    var repositoryRunningTaskIDs: Set<String> {
        get { repo.runningTaskIDs }
        set { repo.runningTaskIDs = newValue }
    }
    var scanCache: LedgerStore.ScanCache {
        get { caches.scanCache }
        set { caches.scanCache = newValue }
    }
    var baseDocuments: [(document: LedgerDocument, isDeleted: Bool)] {
        get { caches.baseDocuments }
        set { caches.baseDocuments = newValue }
    }
    var strengthByHead: [String: EvidenceStrength] {
        get { caches.strengthByHead }
        set { caches.strengthByHead = newValue }
    }
    var domainIndex: [String: String] {
        get { caches.domainIndex }
        set { caches.domainIndex = newValue }
    }
    var kindIndex: [String: String] {
        get { caches.kindIndex }
        set { caches.kindIndex = newValue }
    }
    var knowledgeIndex: [String: String] {
        get { caches.knowledgeIndex }
        set { caches.knowledgeIndex = newValue }
    }
    var cachedAgentEdges: [AgentEdge] {
        get { caches.cachedAgentEdges }
        set { caches.cachedAgentEdges = newValue }
    }
    var documentByHead: [String: LedgerDocument] {
        get { caches.documentByHead }
        set { caches.documentByHead = newValue }
    }
    var openedRepositoryPath: String? {
        get { session.openedRepositoryPath }
        set { session.openedRepositoryPath = newValue }
    }
    var integrityProblemCount: Int {
        get { session.integrityProblemCount }
        set { session.integrityProblemCount = newValue }
    }
    var lastCheckpoint: LedgerObject? {
        get { session.lastCheckpoint }
        set { session.lastCheckpoint = newValue }
    }
    var remoteSyncPercent: Int? {
        get { session.remoteSyncPercent }
        set { session.remoteSyncPercent = newValue }
    }
    var remoteVersioningType: String? {
        get { session.remoteVersioningType }
        set { session.remoteVersioningType = newValue }
    }
    var checkpointJobLoaded: Bool {
        get { session.checkpointJobLoaded }
        set { session.checkpointJobLoaded = newValue }
    }
    var loadedHeadID: String? {
        get { session.loadedHeadID }
        set { session.loadedHeadID = newValue }
    }
    var saveTask: Task<Void, Never>? {
        get { session.saveTask }
        set { session.saveTask = newValue }
    }
    var backStack: [NavSpot] {
        get { session.backStack }
        set { session.backStack = newValue }
    }
    var forwardStack: [NavSpot] {
        get { session.forwardStack }
        set { session.forwardStack = newValue }
    }
    var evidenceDomainFilter: String? {
        get { session.evidenceDomainFilter }
        set { session.evidenceDomainFilter = newValue }
    }
    var evidenceTagFilter: String? {
        get { session.evidenceTagFilter }
        set { session.evidenceTagFilter = newValue }
    }
    var evidenceKnowledgeFilter: String? {
        get { session.evidenceKnowledgeFilter }
        set { session.evidenceKnowledgeFilter = newValue }
    }
}
