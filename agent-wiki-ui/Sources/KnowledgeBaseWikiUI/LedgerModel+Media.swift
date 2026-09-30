import AppKit
import Foundation
import KnowledgeBaseWikiCore

extension LedgerModel {
    /// 선택 객체의 사건 타임라인 — 그 객체를 subject/object 로 삼은 사건들(occurred 순).
    func timeline(for id: String) -> [LedgerGraph.TimelineRow] {
        graphStore?.timeline(of: id) ?? []
    }

    /// blob 원본을 텍스트로(있으면). 바이너리·누락이면 nil.
    func blobText(_ sha: String) -> String? {
        guard let data = blobStore?.get(sha) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func blobData(_ sha: String) -> Data? { blobStore?.get(sha) }
    func blobKind(_ sha: String) -> BlobStore.Kind? { blobStore?.kind(sha) }
    func blobSize(_ sha: String) -> Int? { blobStore?.size(sha) }

    /// 이 원본에 연결된 사건들(역참조) — "무엇에 쓰였나".
    func eventsForBlob(_ sha: String) -> [Event] { eventLog?.eventsReferencing(blob: sha) ?? [] }

    /// 원본을 기본 앱으로 연다 — 임시 파일에 원본 확장자로 쓰고 NSWorkspace 로. PDF·MP3 등.
    func openBlobExternally(_ sha: String) {
        guard let data = blobStore?.get(sha), let kind = blobStore?.kind(sha) else { return }
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("blob-\(sha.prefix(12)).\(kind.ext)")
        do { try data.write(to: tmp); NSWorkspace.shared.open(tmp) }
        catch { errorMessage = "원본 열기 실패: \(error.localizedDescription)" }
    }

    /// 개정 diff — 이 판 vs 이전 판(supersedes). 이전 판 없으면(신규) nil.
    func revisionDiff(_ id: String) -> [DiffLine]? {
        guard let object = objects.first(where: { $0.id == id }),
              let prevID = object.supersedes,
              let prev = objects.first(where: { $0.id == prevID }) else { return nil }
        return TextDiff.lines(prev.body, object.body)
    }

    /// 위키 토론 스레드 — 미답변 우선(나무위키 토론). 사서 처리 대상을 눈에 보이게.
    func discussionThreads() -> [DiscussionThread] { store?.discussionThreads(objects) ?? [] }
    /// 사이드바 배지용 — 미답변 토론 수·경험칙 수.
    var openDiscussionCount: Int { discussionThreads().filter(\.isOpen).count }
    var ruleCount: Int { retrospectives().count }

    /// 학습 지표(일자별) — 경험학습 측정 신호.
    func learningMetrics() -> [PeriodMetrics] {
        guard let root = rootURL else { return [] }
        return LearningMetrics.byDay(objects: objects, events: EventLog(root: root).all())
    }
    /// 경험칙(회고) — 학습 산출물.
    func retrospectives() -> [LedgerObject] {
        store?.heads(objects).filter { $0.effectiveType == "retrospective" && $0.retracts == nil }
            .sorted { ($0.published, $0.id) > ($1.published, $1.id) } ?? []
    }

    /// 지식층 최근 변경 — 신규·개정·철회 피드(나무위키 RecentChanges). 위키가 살아있음을 보인다.
    func recentKnowledgeChanges(limit: Int = 100) -> [KnowledgeChange] {
        store?.recentChanges(objects, limit: limit) ?? []
    }

    /// 전 사건 — 최근(occurred 내림차순) 우선. 사건 타임라인 영역 표시용.
    func allEventsRecentFirst(limit: Int = 500) -> [Event] {
        guard let log = eventLog else { return [] }
        return Array(log.all().reversed().prefix(limit))
    }
}
