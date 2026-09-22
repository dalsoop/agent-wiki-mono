import Foundation

/// 지식층 최근 변경 — 나무위키 RecentChanges 대응. "위키가 살아있음"을 보이는 심장.
/// 사건 로그(운영 사실)와 별개로, 지식 문서(개념·엔티티·근거·색인·결정)의 신규·개정·철회를
/// 시간순으로 보여준다. 정본(md)에서 전부 파생 — 저장 안 함.
public struct KnowledgeChange: Sendable, Equatable {
    public enum Kind: String, Sendable { case new, revised, retracted }
    public let id: String
    public let title: String
    public let type: String
    public let author: String
    public let published: Date
    public let kind: Kind
    public let deltaChars: Int   // 개정: 새 본문−이전 본문 / 신규: +본문 / 철회: 0
    public let reason: String?   // "개정 사유: …" 첫 줄
    public let targetID: String? // 개정·철회 대상(이전 판/철회된 문서) id
}

extension LedgerStore {
    /// 지식 문서의 최근 변경 피드 — 최신순. 절차(run·checkpoint 등)는 제외.
    /// 개정은 이전 판 대비 본문 크기 delta 를, 신규는 +본문, 철회는 대상만 표시.
    public func recentChanges(_ objects: [LedgerObject], limit: Int = 100) -> [KnowledgeChange] {
        let byID = Dictionary(uniqueKeysWithValues: objects.map { ($0.id, $0) })
        var out: [KnowledgeChange] = []
        // id 내림차순 = 시간 내림차순(UUIDv7)
        for object in objects.sorted(by: { ($0.published, $0.id) > ($1.published, $1.id) }) {
            // 지식만 — 절차 발행물 제외. 철회 발행(retracts)은 철회 이벤트로 포함.
            let isKnowledge = !object.isProcess
            if object.retracts == nil && !isKnowledge { continue }

            let kind: KnowledgeChange.Kind
            var delta = 0
            var target: String? = nil
            var title = object.title ?? "(무제)"
            if let retracted = object.retracts {
                kind = .retracted
                target = retracted
                title = byID[retracted]?.title ?? title
            } else if let prev = object.supersedes {
                kind = .revised
                target = prev
                delta = object.body.count - (byID[prev]?.body.count ?? 0)
            } else {
                kind = .new
                delta = object.body.count
            }
            out.append(KnowledgeChange(
                id: object.id, title: title, type: object.effectiveType ?? "?",
                author: object.author, published: object.published, kind: kind,
                deltaChars: delta, reason: Self.editReason(object.body), targetID: target))
            if out.count >= limit { break }
        }
        return out
    }

    /// 본문 첫 줄이 "개정 사유: …" 면 그 사유를 뽑는다.
    static func editReason(_ body: String) -> String? {
        guard let first = body.split(separator: "\n", maxSplits: 1).first else { return nil }
        let line = first.trimmingCharacters(in: .whitespaces)
        guard line.hasPrefix("개정 사유:") else { return nil }
        let reason = line.dropFirst("개정 사유:".count).trimmingCharacters(in: .whitespaces)
        return reason.isEmpty ? nil : reason
    }
}
