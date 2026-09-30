import InteropKit
import AppKit
import Foundation
import KnowledgeBaseWikiCore
import Observation
import StateMirrorKit

/// 사용자에게 보이는 단위는 "문서"다 — 원장 객체(판)의 계보 하나가 문서 하나.
/// 불변 원장은 배관: 저장=개정판 발행, 삭제=철회, 복원=재발행이 밑에서 일어난다.
struct LedgerDocument: Identifiable {
    /// 현재(head) 판.
    let head: LedgerObject
    /// 계보 전체 (head 포함, 새→옛).
    let versions: [LedgerObject]

    var id: String { head.id }
    var title: String { head.title ?? "제목 없음" }
    var snippet: String {
        head.body.split(separator: "\n").first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map(String.init) ?? ""
    }
    var updatedAt: Date { head.published }
}

@MainActor
@Observable
final class LedgerModel {
    var area: LedgerArea = .myNotes
    var destination: RepositoryDestination = .overview
    var rootURL: URL?
    var objects: [LedgerObject] = []
    var selectedDocumentID: String?
    var searchText = ""
    var showDeleted = false
    var errorMessage: String?
    var editorTitle = ""
    var editorBody = ""
    var worlds: [LedgerWorld] = []
    var currentWorldName: String?
    var cliStaleVersion: String?
    var selectedAgentName: String?
    var sortByStrength = false
    var evidenceReviewOnly = false
    var repo = LedgerRepositoryUIState()
    var caches = LedgerDerivedIndex()
    var session = LedgerSessionState()

    var store: LedgerStore? { rootURL.map(LedgerStore.init) }
    var storeForGraph: LedgerStore? { store }

    /// 파생 인덱스(있으면) — 검색을 FTS 로. 100만 대비 (본문 substring 전량 훑기 회피).
    var searchIndex: LedgerIndex? {
        guard let root = rootURL,
              FileManager.default.fileExists(atPath: root.appendingPathComponent("state/index.db").path)
        else { return nil }
        return LedgerIndex(root: root)
    }

    /// 파생 그래프(있으면) — 객체+사건 순회. 타임라인 뷰가 쓴다.
    var graphStore: LedgerGraph? {
        guard let root = rootURL,
              FileManager.default.fileExists(atPath: root.appendingPathComponent("state/graph.db").path)
        else { return nil }
        return LedgerGraph(root: root)
    }

    /// 사건 로그(있으면) — graph.db 없이도 events/*.ndjson 직접 읽음. 사건 영역이 쓴다.
    var eventLog: EventLog? { rootURL.map(EventLog.init) }

    /// 원본 blob 저장소 — 사건의 source sha 로 날것 원본을 연다.
    var blobStore: BlobStore? { rootURL.map(BlobStore.init) }

    static weak var shared: LedgerModel?

    /// PATH 의 안전 CLI. dual-entry resolve 실패 시 product 이름 경로(호출 전 isSafe 재검).
    nonisolated static var cliPath: String {
        DualEntry.resolveCLIPath() ?? HostPlatform.cliBinPath(DualEntry.cliProductName)
    }

    init() {
        applyLaunchConfiguration()
        Self.shared = self
        refreshRepositoryPresentation()
        refreshProtectionStatus()
        checkCLIVersion()
    }
}
