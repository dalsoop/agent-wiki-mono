import Foundation

extension LedgerIndex {
    // MARK: - 경로·계보·역링크

    /// id 접두어, 제목 정확 일치, alias:* 태그 일치, 제목 접두/부분일치 순으로 후보 id 들.
    /// 검색 우선순위: ID 접두/일치 → 제목 정확 일치 → alias:* 태그 일치 → 제목 접두 일치.
    public func resolveIDs(_ query: String) -> [String] {
        let q = query.precomposedStringWithCanonicalMapping.lowercased()
        // 제목·태그 해석은 head(최신판)만 — "그 이름의 지금 것". 단 id 접두어는 **특정 객체 지목**이라
        let headFilter = """
            retracts IS NULL \
            AND id NOT IN (SELECT supersedes FROM objects WHERE supersedes IS NOT NULL) \
            AND id NOT IN (SELECT retracts FROM objects WHERE retracts IS NOT NULL)
            """

        // 1) id 접두/일치 (모든 판 — head 제한 없음)
        let byPrefix: [String] = db.prepared(
            "SELECT id FROM objects WHERE id LIKE ? LIMIT 25;") { s in
            s.bind(1, q + "%"); var ids: [String] = []
            while s.step() { if let id = s.text(0) { ids.append(id) } }
            return ids
        } ?? []
        if !byPrefix.isEmpty { return byPrefix }

        // 2) 제목 정확 일치 (head 만)
        let byExactTitle: [String] = db.prepared(
            "SELECT id FROM objects WHERE lower(title) = ? AND \(headFilter) ORDER BY published DESC LIMIT 25;") { s in
            s.bind(1, q); var ids: [String] = []
            while s.step() { if let id = s.text(0) { ids.append(id) } }
            return ids
        } ?? []
        if !byExactTitle.isEmpty { return byExactTitle }

        // 3) alias:* 태그 일치 (head 만)
        let targetAlias = q.hasPrefix("alias:") ? q : "alias:" + q
        let escapedAlias = targetAlias
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        let byAlias: [String] = db.prepared(
            "SELECT id FROM objects WHERE (',' || lower(tags) || ',') LIKE ? ESCAPE '\\' AND \(headFilter) ORDER BY published DESC LIMIT 25;") { s in
            s.bind(1, "%," + escapedAlias + ",%"); var ids: [String] = []
            while s.step() { if let id = s.text(0) { ids.append(id) } }
            return ids
        } ?? []
        if !byAlias.isEmpty { return byAlias }

        // 4) 제목 접두 일치 (head 만)
        let escapedQuery = q
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        let byTitlePrefix: [String] = db.prepared(
            "SELECT id FROM objects WHERE lower(title) LIKE ? ESCAPE '\\' AND \(headFilter) ORDER BY published DESC LIMIT 25;") { s in
            s.bind(1, escapedQuery + "%"); var ids: [String] = []
            while s.step() { if let id = s.text(0) { ids.append(id) } }
            return ids
        } ?? []
        if !byTitlePrefix.isEmpty { return byTitlePrefix }

        // 5) 제목 부분일치 (head 만 fallback)
        return db.prepared(
            "SELECT id FROM objects WHERE lower(title) LIKE ? ESCAPE '\\' AND \(headFilter) ORDER BY published DESC LIMIT 25;") { s in
            s.bind(1, "%" + escapedQuery + "%"); var ids: [String] = []
            while s.step() { if let id = s.text(0) { ids.append(id) } }
            return ids
        } ?? []
    }

    /// id → md 파일 절대경로(파일 1개만 읽어 본문 로드용).
    public func pathFor(id: String) -> String? {
        db.prepared("SELECT path FROM files WHERE id=? LIMIT 1;") { s in
            s.bind(1, id); return s.step() ? s.text(0) : nil
        } ?? nil
    }

    /// head(또는 all) 메타 목록 — list 용. 파일 스캔 0.
    public func headRows(all: Bool) -> [HeadRow] {
        let sql = all
            ? "SELECT id,title,author,published,supersedes,retracts,batch FROM objects ORDER BY published, id;"
            : """
            SELECT id,title,author,published,supersedes,retracts,batch FROM objects \
            WHERE retracts IS NULL \
            AND id NOT IN (SELECT supersedes FROM objects WHERE supersedes IS NOT NULL) \
            AND id NOT IN (SELECT retracts FROM objects WHERE retracts IS NOT NULL) \
            ORDER BY published, id;
            """
        return db.prepared(sql) { s in
            var rows: [HeadRow] = []
            while s.step() {
                rows.append(HeadRow(id: s.text(0) ?? "", title: s.text(1), author: s.text(2) ?? "?",
                                    published: s.text(3) ?? "", supersedes: s.text(4),
                                    retracts: s.text(5), batch: s.text(6)))
            }
            return rows
        } ?? []
    }

    private func metaRow(_ id: String) -> HeadRow? {
        let sql = """
            SELECT id,title,author,published,supersedes,retracts,batch \
            FROM objects WHERE id=? LIMIT 1;
            """
        return db.prepared(sql) { s in
            s.bind(1, id)
            guard s.step() else { return HeadRow?.none }
            return HeadRow(id: s.text(0) ?? "", title: s.text(1), author: s.text(2) ?? "?",
                           published: s.text(3) ?? "", supersedes: s.text(4), retracts: s.text(5), batch: s.text(6))
        } ?? nil
    }

    /// 노드 라벨(제목·작성자) — path 렌더용. 없으면 (nil, "?").
    public func titleAuthor(_ id: String) -> (title: String?, author: String) {
        guard let m = metaRow(id) else { return (nil, "?") }
        return (m.title, m.author)
    }

    /// 개정 계보 — 주어진 id 에서 supersedes 를 따라 과거로(store.lineage 와 동일 의미). 파일 스캔 0.
    public func lineage(of id: String) -> [HeadRow] {
        var chain: [HeadRow] = []
        var current: String? = id
        while let cid = current, chain.count < 1000 {
            guard let row = metaRow(cid) else { break }
            chain.append(row)
            current = row.supersedes
        }
        return chain
    }

    /// 역링크 — 이 객체를 인용한 것들(cites.dst=id). rel 은 콤마로 합침. 파일 스캔 0.
    public func citers(of dst: String) -> [Citer] {
        var relsBySrc: [String: [String]] = [:]
        var order: [String] = []
        db.prepared("SELECT src, rel FROM cites WHERE dst=?;") { s in
            s.bind(1, dst)
            while s.step() {
                let src = s.text(0) ?? ""
                if relsBySrc[src] == nil { order.append(src) }
                relsBySrc[src, default: []].append(s.text(1) ?? "")
            }
        }
        // 정본 스캔(citedBy)은 objects 가 id 오름차순이라 그 순서를 따른다 → id 정렬로 출력 일치.
        return order.sorted().compactMap { src -> Citer? in
            guard let m = metaRow(src) else { return nil }
            return Citer(id: src, title: m.title, author: m.author, rels: (relsBySrc[src] ?? []).joined(separator: ","))
        }
    }

    /// 인용/개정 간선 전체(path BFS 용). cites + supersedes. 파일 스캔 0.
    public func citeEdges() -> [(src: String, dst: String, rel: String)] {
        db.prepared("SELECT src,dst,rel FROM cites;") { s -> [(String,String,String)] in
            var out: [(String,String,String)] = []
            while s.step() { out.append((s.text(0) ?? "", s.text(1) ?? "", s.text(2) ?? "")) }
            return out
        } ?? []
    }
    public func supersedesEdges() -> [(id: String, target: String)] {
        db.prepared("SELECT id,supersedes FROM objects WHERE supersedes IS NOT NULL;") { s -> [(String,String)] in
            var out: [(String,String)] = []
            while s.step() { out.append((s.text(0) ?? "", s.text(1) ?? "")) }
            return out
        } ?? []
    }
}
