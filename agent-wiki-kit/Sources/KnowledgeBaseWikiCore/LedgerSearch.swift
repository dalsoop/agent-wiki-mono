import Foundation

/// 키워드 랭킹 조회 — CLI·앱 공용. 제목×3 · 태그×2 · 본문×1 가중 합산,
/// 절차 발행물(isProcess)과 철회 발행은 제외한다.
public struct LedgerSearch: Sendable {
    public struct Hit: Sendable {
        public let object: LedgerObject
        public let score: Int
        public let domain: String?
        public let kind: String?
        public let knowledge: String?
        public let strength: EvidenceStrength
    }

    public let hits: [Hit]

    public init(
        store: LedgerStore, objects: [LedgerObject], query: String,
        domain: String? = nil, kind: String? = nil, knowledge: String? = nil
    ) {
        // macOS 파일계 유입 제목이 NFD 일 수 있어 양쪽 다 NFC 정규화 후 대조
        let terms = query.precomposedStringWithCanonicalMapping.lowercased()
            .split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !terms.isEmpty else { self.hits = []; return }
        let heads = store.heads(objects)
        let classification = LedgerClassification(objects: objects)
        func score(_ object: LedgerObject) -> Int {
            let title = (object.title ?? "").precomposedStringWithCanonicalMapping.lowercased()
            let tags = object.tags.joined(separator: " ").precomposedStringWithCanonicalMapping.lowercased()
            let body = object.body.precomposedStringWithCanonicalMapping.lowercased()
            var total = 0
            for term in terms {
                if title.contains(term) { total += 3 }
                if tags.contains(term) { total += 2 }
                if body.contains(term) { total += 1 }
            }
            return total
        }
        var ranked = heads
            .filter { !$0.isProcess && $0.retracts == nil }
            .map { object in
                Hit(object: object, score: score(object),
                    domain: classification.domain[object.id],
                    kind: classification.kind[object.id],
                    knowledge: classification.knowledge[object.id],
                    strength: store.strength(objects, of: object))
            }
            .filter { $0.score > 0 }
            .sorted { $0.score > $1.score }
        if let domain { ranked = ranked.filter { $0.domain == domain } }
        if let kind { ranked = ranked.filter { $0.kind == kind } }
        if let knowledge { ranked = ranked.filter { $0.knowledge == knowledge } }
        self.hits = ranked
    }
}
