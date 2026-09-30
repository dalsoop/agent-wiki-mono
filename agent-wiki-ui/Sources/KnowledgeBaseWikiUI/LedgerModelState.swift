import Foundation
import KnowledgeBaseWikiCore

/// 저장소 개요·승격·작업 액션 상태. `LedgerModel` 필드 한도를 넘지 않게 묶는다.
struct LedgerRepositoryUIState {
    var identity: RepositoryIdentity?
    var summary: RepositorySummaryContract?
    var worldPickerItems: [WorldPickerItem] = []
    var promotionPreview: PromotionPreview?
    var promotionResult: PromotionResult?
    var promotionMessage: String?
    var promotionMessageIsError = false
    var actionMessage: String?
    var actionIsError = false
    var runningTaskIDs: Set<String> = []
}

/// 파생 인덱스 — 객체가 바뀔 때만 재구축.
struct LedgerDerivedIndex {
    var scanCache = LedgerStore.ScanCache()
    var baseDocuments: [(document: LedgerDocument, isDeleted: Bool)] = []
    var strengthByHead: [String: EvidenceStrength] = [:]
    var domainIndex: [String: String] = [:]
    var kindIndex: [String: String] = [:]
    var knowledgeIndex: [String: String] = [:]
    var cachedAgentEdges: [LedgerModel.AgentEdge] = []
    var documentByHead: [String: LedgerDocument] = [:]
}

/// 보호·편집 세션·항해·필터처럼 화면 바인딩이 아닌 운용 상태.
struct LedgerSessionState {
    var openedRepositoryPath: String?
    var integrityProblemCount = 0
    var lastCheckpoint: LedgerObject?
    var remoteSyncPercent: Int?
    var remoteVersioningType: String?
    var checkpointJobLoaded = false
    var loadedHeadID: String?
    var saveTask: Task<Void, Never>?
    var refreshTimer: Timer?
    var lastCLICheck: Date?
    var backStack: [LedgerModel.NavSpot] = []
    var forwardStack: [LedgerModel.NavSpot] = []
    var evidenceDomainFilter: String?
    var evidenceTagFilter: String?
    var evidenceKnowledgeFilter: String?
}
