import Foundation

// ledger 3 원장의 범위 검색 — 범위는 `WorldSearchScope.entries`(같은 원장·상위·그 각각의 전신)이고
// 범위 안 각 world 를 그 형식대로 읽어 같은 점수 규칙(`LedgerSearch`)으로 순위를 매긴다.
// CLI(`search`·`context`)와 화면(기록 목록)이 이 한 곳을 쓴다. 전신 결과의 표시는 `LawScopedSearch.mark`.
// 근거: docs/business-rules.md "전신"(검색·컨텍스트 범위도 같고 전신 객체에는 표시가 붙는다).

public struct LawSearchHit: Sendable {
    public let item: LawScopeObject
    public let score: Int

    public init(item: LawScopeObject, score: Int) {
        self.item = item
        self.score = score
    }
}

public enum LawScopedSearch {
    /// 범위 안 각 world 를 그 형식대로 읽어 같은 점수 규칙으로 순위를 매긴다(점수 높은 순, `limit` 개).
    /// 옛 분류 거르기(`domain`·`kind`·`knowledge`)는 ledger 2 world 에만 적용한다.
    public static func hits(index: LawScopeIndex, parsed: WorldScopedSearchParse) -> [LawSearchHit] {
        var merged: [LawSearchHit] = []
        for entry in index.entries {
            let items = index.objects.filter { $0.world == entry.name }
            guard let world = index.catalog.world(named: entry.name), !items.isEmpty else { continue }
            let ledgerThree = index.catalog.isLedgerThree(entry.name)
            let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let search = LedgerSearch(
                store: LedgerStore(root: URL(fileURLWithPath: world.rootPath)), objects: items.map(\.object),
                query: parsed.queryText,
                domain: ledgerThree ? nil : parsed.domainFilter, kind: ledgerThree ? nil : parsed.kindFilter,
                knowledge: ledgerThree ? nil : parsed.knowledgeFilter)
            for hit in search.hits {
                guard let item = byID[hit.object.id] else { continue }
                merged.append(LawSearchHit(item: item, score: hit.score))
            }
        }
        return Array(merged.sorted { $0.score > $1.score }.prefix(parsed.limit))
    }

    /// 결과 표시 — 전신이면 `[전신 <world>]`, 상위 원장이면 `[상위 <world>]`, 같은 원장이면 빈 문자열.
    public static func mark(_ item: LawScopeObject, current: String) -> String {
        if item.isPredecessor { return "[전신 \(item.world)]" }
        if item.world != current { return "[상위 \(item.world)]" }
        return ""
    }
}
