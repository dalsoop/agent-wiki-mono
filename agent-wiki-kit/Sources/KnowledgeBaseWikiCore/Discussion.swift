import Foundation

/// 위키 토론 스레드 — 나무위키 토론(Discussion) 대응. 이의·질문·수정요청을 문서별 스레드로,
/// 응답 유무로 미답변/답변됨 상태를 매긴다. 사서(wiki-maintainer)의 '미응답 토론 최우선'을
/// 눈에 보이게 만든다. md 정본에서 파생.
public struct DiscussionThread: Sendable, Equatable {
    public enum Kind: String, Sendable {
        case question, objection, editRequest, other
        public var label: String {
            switch self { case .question: "질문"; case .objection: "이의"
                          case .editRequest: "수정요청"; case .other: "토론" }
        }
    }
    public let topicID: String
    public let title: String
    public let author: String
    public let targetID: String        // 토론 대상 문서 id
    public let kind: Kind
    public let responseCount: Int
    public let isOpen: Bool             // 응답 없음 = 미답변(사서가 처리해야 함)
    public let opened: Date
    public let lastActivity: Date
}

extension LedgerStore {
    // 에이전트가 즉흥으로 type: discuss 로 발행하기도 한다(2026-07-20 실측: retrospective 가
    // 자기 역할 수정요청을 type=discuss 로 냄) → 토론에 안 뜨던 버그. discuss 도 인식한다.
    private static let discussionTypes: Set<String> = ["objection", "question", "edit-request", "discuss"]

    /// 종류 판정 — 제목 접두사 우선(type 이 generic discuss 여도 수정요청/이의/질문을 살린다), 그다음 type.
    private static func discussionKind(title: String?, type: String?) -> DiscussionThread.Kind {
        let t = (title ?? "").trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("수정요청") { return .editRequest }
        if t.hasPrefix("이의") { return .objection }
        if t.hasPrefix("질문") { return .question }
        switch type {
        case "edit-request": return .editRequest
        case "objection": return .objection
        case "question": return .question
        default: return .other
        }
    }

    /// 토론 스레드 목록 — 미답변 우선, 그다음 최근 활동순. target 주면 그 문서 것만.
    public func discussionThreads(_ objects: [LedgerObject], target: String? = nil) -> [DiscussionThread] {
        // 응답 색인: 어떤 토론을 인용한 발행물 수/최근시각
        var responsesByTopic: [String: (count: Int, last: Date)] = [:]
        for object in objects {
            for cite in object.cites {
                var entry = responsesByTopic[cite.id] ?? (0, .distantPast)
                entry.count += 1
                entry.last = max(entry.last, object.published)
                responsesByTopic[cite.id] = entry
            }
        }
        var threads: [DiscussionThread] = []
        for object in objects where Self.discussionTypes.contains(object.effectiveType ?? "") {
            let citedDocs = object.cites.map(\.id)
            if let target, !citedDocs.contains(target) { continue }
            // 대상 문서 = 첫 인용(토론은 문서를 cite 한다)
            let targetID = citedDocs.first ?? ""
            // 응답 = 이 토론을 인용한 발행물. 단 자기 대상 문서 인용은 응답이 아님 — 토론 id 인용만.
            let resp = responsesByTopic[object.id] ?? (0, object.published)
            let kind = Self.discussionKind(title: object.title, type: object.effectiveType)
            threads.append(DiscussionThread(
                topicID: object.id, title: object.title ?? "(무제)", author: object.author,
                targetID: targetID, kind: kind, responseCount: resp.count,
                isOpen: resp.count == 0, opened: object.published,
                lastActivity: resp.count == 0 ? object.published : resp.last))
        }
        return threads.sorted { a, b in
            if a.isOpen != b.isOpen { return a.isOpen }       // 미답변 먼저
            return a.lastActivity > b.lastActivity             // 그다음 최근
        }
    }
}
