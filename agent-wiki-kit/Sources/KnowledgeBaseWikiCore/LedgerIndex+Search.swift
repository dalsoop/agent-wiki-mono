import Foundation

extension LedgerIndex {
    // MARK: - 조회 (파일 스캔 없이)

    /// FTS5 쿼리 조립. **각 토큰을 큰따옴표로 감싼다** — bareword 는 하이픈 등 예약문자를
    /// 담을 수 없어서, `agent-vault*` 같은 걸 그대로 넘기면 문법 오류가 나고 그 오류가
    /// 삼켜져 "결과 없음"으로 보인다. 이 Mac 의 이름은 대부분 kebab-case 라
    /// (`agent-vault` · `gujo-swift` · `k3s-prod`) 가장 자주 치는 질의가 통째로 죽었었다.
    func ftsTerms(_ query: String) -> String {
        query.precomposedStringWithCanonicalMapping
            .split(whereSeparator: { $0.isWhitespace })
            .map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"*" }
            .joined(separator: " ")
    }

    /// 타입 무관 FTS id 검색 — 앱 전 영역 검색용(활동·내기록 포함). 매칭 id 만.
    public func searchAllIDs(_ query: String, limit: Int = 500) -> [String] {
        let terms = ftsTerms(query)
        guard !terms.isEmpty else { return [] }
        return db.prepared("SELECT id FROM fts WHERE fts MATCH ? ORDER BY bm25(fts) LIMIT ?;") { stmt -> [String] in
            stmt.bind(1, terms); stmt.bind(2, Int64(limit))
            var ids: [String] = []
            while stmt.step() { if let id = stmt.text(0) { ids.append(id) } }
            return ids
        } ?? []
    }

    /// FTS 검색 — 제목·본문·태그. 절차/철회 제외, 지식 head 만. 파일 스캔 0.
    /// 절차-type 필터는 LedgerObject.processTypesSQL 단일원에서 파생(하드코딩 금지).
    public func search(_ query: String, domain: String? = nil, kind: String? = nil,
                       knowledge: String? = nil, limit: Int = 8) -> [Row] {
        let terms = ftsTerms(query)
        guard !terms.isEmpty else { return [] }
        var sql = """
        SELECT o.id,o.title,o.type,o.author,o.domain,o.kind,o.knowledge,
               bm25(fts) AS rank
        FROM fts JOIN objects o ON o.id = fts.id
        WHERE fts MATCH ? AND o.retracts IS NULL
          AND o.type NOT IN (\(LedgerObject.processTypesSQL))
          AND o.id NOT IN (SELECT supersedes FROM objects WHERE supersedes IS NOT NULL)
        """
        if domain != nil { sql += " AND o.domain=?" }
        if kind != nil { sql += " AND o.kind=?" }
        if knowledge != nil { sql += " AND o.knowledge=?" }
        sql += " ORDER BY rank LIMIT ?;"
        return db.prepared(sql) { stmt -> [Row] in
            var i: Int32 = 1
            stmt.bind(i, terms); i += 1
            for v in [domain, kind, knowledge] where v != nil { stmt.bind(i, v); i += 1 }
            stmt.bind(i, Int64(limit))
            var rows: [Row] = []
            while stmt.step() {
                rows.append(Row(id: stmt.text(0)!, title: stmt.text(1), type: stmt.text(2),
                                author: stmt.text(3) ?? "?", domain: stmt.text(4),
                                kind: stmt.text(5), knowledge: stmt.text(6)))
            }
            return rows
        } ?? []
    }
}
