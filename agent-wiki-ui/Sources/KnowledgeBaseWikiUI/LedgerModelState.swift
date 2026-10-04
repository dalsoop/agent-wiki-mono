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
    var refresh = LedgerRefreshState()
    var lastCLICheck: Date?
    var backStack: [LedgerModel.NavSpot] = []
    var forwardStack: [LedgerModel.NavSpot] = []
    var evidenceDomainFilter: String?
    var evidenceTagFilter: String?
    var evidenceKnowledgeFilter: String?
}

/// ledger 3 원장 화면 상태 — 표시 모델은 엔진(`KnowledgeBaseWikiCore` 의 `Law*Screen`)이 만들고, 화면은 배경 읽기 결과만 받는다.
struct LedgerLawUIState {
    /// 지금 연 원장의 화면 판정(설정 기반). 배경 읽기가 채운다.
    var kind: LawLedgerScreenKind?
    /// 마지막으로 읽은 원장 `objects/` 의 변화 표지 — 같으면 2초 갱신이 원장을 다시 읽지 않는다.
    var fingerprint: LawObjectsFingerprint?
    var contents: LawContentsScreen?
    var court: LawCourtScreen?
    var dream: LawDreamScreen?
    var credibility: LawCredibilityScreen?
    var credibilityPeriod: LawCredibilityPeriod = .all
    var records: [LawRecordListRow] = []
    var recordFilter = LawRecordListFilter()
    /// 기록 상세로 연 기록 id(`showLawRecord(id:)`).
    var selectedRecordID: String?
    var recordDetail: LawRecordDetail?
    /// 기록 상세에서 편집을 연 상태 — 기존 편집기(`select`·`editorChanged`, 저장 = 개정 공포)를 그대로 쓴다.
    var isEditingRecord = false
    /// 드리밍 묶음 하나를 눌렀을 때 그 묶음이 바꾼 기록.
    var selectedBatch: String?
    var batchChanges: [LawBatchChange] = []
    /// 되돌리기·재개 결과(거부 이유 포함).
    var actionMessage: String?
    var actionIsError = false
}

/// 배경 새로고침 상태 — 겹쳐 돌지 않게 한 번에 하나만 돌리고, 도는 중이거나 결과를 반영하는 중에 들어온 요청은
/// 끝난 뒤 한 번만 더 돌린다. 쓰기 직후 할 일(`refresh(then:)`)은 그 쓰기 뒤에 시작한 읽기의 결과를 반영한 다음에 부른다.
struct LedgerRefreshState {
    var inFlight = false
    /// 결과를 반영하는 중(반영이 부른 다시 읽기는 끝에서 한 번만 돈다).
    var applying = false
    var pending = false
    /// 다음 새로고침이 객체 변경과 무관하게 화면 표시 모델을 다시 읽어야 하는가(필터·기간·선택 변경).
    var forceLawReload = false
    /// 다음에 시작할 읽기의 결과를 반영한 뒤 부를 일. 도는 중에 들어온 일은 그 다음 읽기(쓰기 뒤 읽기)를 기다린다.
    var waiting: [@MainActor () -> Void] = []
    /// 지금 도는 읽기의 결과를 반영한 뒤 부를 일.
    var running: [@MainActor () -> Void] = []

    /// 읽기 요청. 지금 시작해도 되면 true — 기다리던 일을 이 읽기가 맡는다. 아니면 false(끝난 뒤 한 번 더).
    mutating func request(then: (@MainActor () -> Void)?) -> Bool {
        if let then { waiting.append(then) }
        guard !inFlight, !applying else {
            pending = true
            return false
        }
        inFlight = true
        pending = false
        running = waiting
        waiting = []
        return true
    }

    /// 읽기 결과가 왔다 — 반영을 시작하고, 이 읽기가 맡은 일을 꺼낸다.
    mutating func beginApply() -> [@MainActor () -> Void] {
        inFlight = false
        applying = true
        let taken = running
        running = []
        return taken
    }

    /// 결과를 버리고 다시 읽는다 — 맡았던 일은 다음 읽기로 넘긴다.
    mutating func discard(_ taken: [@MainActor () -> Void]) {
        applying = false
        waiting = taken + waiting
        forceLawReload = true
        pending = true
    }

    /// 반영 끝. 그 사이 들어온 요청이 있으면 true(한 번 더 읽는다).
    mutating func endApply() -> Bool {
        applying = false
        return pending
    }
}
