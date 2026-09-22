import Foundation

extension LedgerIndex {
    // MARK: - blob 역참조·원문 검색

    /// 객체 → 원본 역참조를 다시 계산한다. blob 집합이나 객체가 바뀌면 전부 다시 본다 —
    /// 규모가 작고(원본 수십 개), 부분 갱신은 "빠뜨린 참조" 라는 조용한 결함을 만든다.
    public func recomputeBlobRefs(root: URL) {
        var shas: Set<String> = []
        db.prepared("SELECT sha FROM blobs;") { stmt in
            while stmt.step() { if let s = stmt.text(0) { shas.insert(s) } }
        }
        db.exec("BEGIN;")
        db.exec("DELETE FROM blobrefs;")
        if !shas.isEmpty {
            for object in LedgerStore(root: root).scan() {
                var seen: Set<String> = []
                if let typed = object.source?.blob, shas.contains(typed) {
                    insertBlobRef(object: object.id, sha: typed, via: "typed")
                    seen.insert(typed)
                }
                guard object.body.count >= 64 else { continue }
                for sha in shas where !seen.contains(sha) && object.body.contains(sha) {
                    insertBlobRef(object: object.id, sha: sha, via: "body")
                    seen.insert(sha)
                }
            }
        }
        db.exec("COMMIT;")
    }

    private func insertBlobRef(object: String, sha: String, via: String) {
        db.prepared("INSERT INTO blobrefs(object,sha,via) VALUES(?,?,?);") { s in
            s.bind(1, object); s.bind(2, sha); s.bind(3, via); s.step()
        }
    }

    public func objectsReferencing(blob sha: String) -> [BlobRef] {
        db.prepared("""
            SELECT r.object, r.via, o.title FROM blobrefs r
            LEFT JOIN objects o ON o.id = r.object WHERE r.sha = ? ORDER BY r.via, r.object;
            """) { stmt -> [BlobRef] in
            stmt.bind(1, sha)
            var out: [BlobRef] = []
            while stmt.step() {
                out.append(BlobRef(object: stmt.text(0) ?? "", via: stmt.text(1) ?? "?",
                                   title: stmt.text(2)))
            }
            return out
        } ?? []
    }

    /// sha 접두어 → 전체 sha. 유일하지 않으면 nil(호출측이 원문 그대로 시도).
    public func resolveBlobSHA(_ prefix: String) -> String? {
        var out: [String] = []
        db.prepared("SELECT sha FROM blobs WHERE sha LIKE ? LIMIT 2;") { stmt in
            stmt.bind(1, prefix.lowercased() + "%")
            while stmt.step() { if let s = stmt.text(0) { out.append(s) } }
        }
        return out.count == 1 ? out[0] : nil
    }

    /// 어떤 객체든 가리키고 있는 원본 sha 집합 — gc 도달성의 절반.
    public func referencedBlobSHAs() -> Set<String> {
        var out: Set<String> = []
        db.prepared("SELECT DISTINCT sha FROM blobrefs;") { stmt in
            while stmt.step() { if let s = stmt.text(0) { out.insert(s) } }
        }
        return out
    }

    /// via 별 원본 수 — 구조 진단이 "typed 로 옮길 후보"를 센다.
    public func blobRefCounts() -> (typed: Int, body: Int) {
        func distinct(_ via: String) -> Int {
            db.scalarInt("SELECT COUNT(DISTINCT sha) FROM blobrefs WHERE via='\(via)';") ?? 0
        }
        return (distinct("typed"), distinct("body"))
    }
    /// 텍스트 원본 검색 — 객체가 아니라 **봉인된 원문**을 찾는다. 객체 검색과 표를 나눠
    /// 두는 건 둘의 성격이 달라서다: 객체는 해석이고 blob 은 날것이다.
    public func searchBlobs(_ query: String, limit: Int = 5) -> [BlobHit] {
        let terms = ftsTerms(query)
        guard !terms.isEmpty else { return [] }
        return db.prepared("""
            SELECT b.sha, b.size, b.kind, snippet(fts, 2, '', '', '…', 12) AS s
            FROM fts JOIN blobs b ON b.sha = fts.id
            WHERE fts MATCH ? ORDER BY bm25(fts) LIMIT ?;
            """) { stmt -> [BlobHit] in
            stmt.bind(1, terms); stmt.bind(2, Int64(limit))
            var out: [BlobHit] = []
            while stmt.step() {
                out.append(BlobHit(sha: stmt.text(0) ?? "", size: Int(stmt.int(1)),
                                   kind: stmt.text(2) ?? "?",
                                   snippet: (stmt.text(3) ?? "").replacingOccurrences(of: "\n", with: " ")))
            }
            return out
        } ?? []
    }

    /// fts 행 중 **객체**인 것만 — blob 행이 섞여 객체 색인율을 부풀리지 않게.
    /// 색인된 원본 수(바이너리 포함 — 종류 기록용 행도 센다).
    public func blobRowCount() -> Int { db.scalarInt("SELECT COUNT(*) FROM blobs;") ?? 0 }

    public func ftsObjectRowCount() -> Int {
        db.scalarInt("SELECT COUNT(*) FROM fts JOIN objects o ON o.id = fts.id;") ?? 0
    }
}
