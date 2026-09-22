import Foundation

extension LedgerIndex {
    // MARK: - 증분 동기화 (md → index)

    /// objects/ 를 훑어 바뀐 파일만 재파싱해 인덱스 갱신. 삭제된 파일은 인덱스에서 제거.
    /// 반환: (추가·변경 수, 삭제 수). md 정본에서 언제든 재구성 가능.
    @discardableResult
    public func sync(objectsDir: URL) -> (upserted: Int, removed: Int) {
        var known: [String: (mtime: Double, size: Int)] = [:]
        db.prepared("SELECT path, mtime, size FROM files;") { stmt in
            while stmt.step() {
                known[stmt.text(0) ?? ""] = (stmt.double(1), Int(stmt.int(2)))
            }
        }

        var seen = Set<String>()
        var upserted = 0
        db.exec("BEGIN;")
        if let enumerator = FileManager.default.enumerator(
            at: objectsDir, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]) {
            for case let url as URL in enumerator where url.pathExtension == "md" {
                let p = url.path
                seen.insert(p)
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                let mtime = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
                let size = values?.fileSize ?? -1
                if let k = known[p], k.mtime == mtime, k.size == size { continue }
                guard let text = try? String(contentsOf: url, encoding: .utf8),
                      let parsed = LedgerObject.parse(text) else { continue }
                upsert(parsed.object, path: p, mtime: mtime, size: size)
                upserted += 1
            }
        }
        var removed = 0
        for p in Set(known.keys).subtracting(seen) {
            deleteByPath(p); removed += 1
        }
        db.exec("COMMIT;")
        // 분류(도메인/kind/knowledge)는 cites 전체를 봐야 해서 갱신이 있으면 재계산
        if upserted > 0 || removed > 0 { recomputeClassification() }
        return (upserted, removed)
    }

    /// blobs/ 를 훑어 **텍스트 blob 내용**을 fts 에 반영한다. 바이너리(PNG·PDF·음원)는
    /// 색인하지 않는다 — 본문이 없어서 검색어가 걸릴 수 없고 fts 만 부풀린다.
    /// 변경 판정은 (mtime, size). blob 은 write-once 라 사실상 추가·삭제만 일어난다.
    @discardableResult
    public func syncBlobs(root: URL) -> (indexed: Int, removed: Int) {
        let store = BlobStore(root: root)
        var known: [String: (mtime: Double, size: Int)] = [:]
        db.prepared("SELECT sha, mtime, size FROM blobs;") { stmt in
            while stmt.step() {
                known[stmt.text(0) ?? ""] = (stmt.double(1), Int(stmt.int(2)))
            }
        }
        let onDisk = Set(store.allSHAs())
        var indexed = 0
        db.exec("BEGIN;")
        for sha in onDisk {
            let url = store.url(for: sha)
            let v = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let mtime = v?.contentModificationDate?.timeIntervalSince1970 ?? 0
            let size = v?.fileSize ?? -1
            if let k = known[sha], k.mtime == mtime, k.size == size { continue }
            guard let data = store.get(sha) else { continue }
            let kind = BlobStore.sniff(data)
            // 종류는 바이너리도 기록한다 — "색인 대상이 아님"을 아는 것도 정보다.
            db.prepared("INSERT OR REPLACE INTO blobs(sha,size,kind,mtime) VALUES(?,?,?,?);") { s in
                s.bind(1, sha); s.bind(2, Int64(size)); s.bind(3, kind.label); s.bind(4, mtime); s.step()
            }
            db.prepared("DELETE FROM fts WHERE id=?;") { $0.bind(1, sha); $0.step() }
            guard kind.isText else { indexed += 1; continue }
            let text = String(decoding: data.prefix(Self.blobTextIndexLimit), as: UTF8.self)
                .precomposedStringWithCanonicalMapping
            db.prepared("INSERT INTO fts(id,title,body,tags) VALUES(?,?,?,?);") { s in
                s.bind(1, sha); s.bind(2, nil); s.bind(3, text); s.bind(4, "blob"); s.step()
            }
            indexed += 1
        }
        var removed = 0
        for sha in Set(known.keys).subtracting(onDisk) {
            db.prepared("DELETE FROM blobs WHERE sha=?;") { $0.bind(1, sha); $0.step() }
            db.prepared("DELETE FROM fts WHERE id=?;") { $0.bind(1, sha); $0.step() }
            removed += 1
        }
        db.exec("COMMIT;")
        recomputeBlobRefs(root: root)
        return (indexed, removed)
    }

    private func upsert(_ o: LedgerObject, path: String, mtime: Double, size: Int) {
        // 기존 행 제거 후 삽입 (fts·cites 포함)
        deleteByID(o.id)
        db.prepared("INSERT INTO objects(id,title,type,author,published,tags,origin,batch,supersedes,retracts,sha256,mtime,size,domain,kind,knowledge) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,NULL,NULL,NULL);") { s in
            s.bind(1, o.id); s.bind(2, o.title); s.bind(3, o.effectiveType)
            s.bind(4, o.author); s.bind(5, LedgerObject.iso.string(from: o.published))
            s.bind(6, o.tags.joined(separator: ",")); s.bind(7, o.origin); s.bind(8, o.batch)
            s.bind(9, o.supersedes); s.bind(10, o.retracts); s.bind(11, o.sha256)
            s.bind(12, mtime); s.bind(13, Int64(size))
            s.step()
        }
        db.prepared("INSERT OR REPLACE INTO files(path,id,mtime,size) VALUES(?,?,?,?);") { s in
            s.bind(1, path); s.bind(2, o.id); s.bind(3, mtime); s.bind(4, Int64(size)); s.step()
        }
        db.prepared("INSERT INTO fts(id,title,body,tags) VALUES(?,?,?,?);") { s in
            s.bind(1, o.id); s.bind(2, o.title?.precomposedStringWithCanonicalMapping)
            s.bind(3, o.body.precomposedStringWithCanonicalMapping)
            s.bind(4, o.tags.joined(separator: " ").precomposedStringWithCanonicalMapping)
            s.step()
        }
        for cite in o.cites {
            db.prepared("INSERT INTO cites(src,dst,rel) VALUES(?,?,?);") { s in
                s.bind(1, o.id); s.bind(2, cite.id); s.bind(3, cite.rel); s.step()
            }
        }
    }

    private func deleteByID(_ id: String) {
        for sql in ["DELETE FROM objects WHERE id=?;", "DELETE FROM fts WHERE id=?;",
                    "DELETE FROM cites WHERE src=?;", "DELETE FROM files WHERE id=?;"] {
            db.prepared(sql) { $0.bind(1, id); $0.step() }
        }
    }

    private func deleteByPath(_ path: String) {
        let id: String? = db.prepared("SELECT id FROM files WHERE path=?;") { stmt in
            stmt.bind(1, path)
            return stmt.step() ? stmt.text(0) : nil
        } ?? nil
        if let id { deleteByID(id) }
    }

    /// 분류 스탬프(rel=screens)의 domain/kind/knowledge 를 계보 head 로 승격해 objects 컬럼에 반영.
    private func recomputeClassification() {
        db.exec("UPDATE objects SET domain=NULL, kind=NULL, knowledge=NULL;")
        // successor 맵
        var successor: [String: String] = [:]
        db.prepared("SELECT id, supersedes FROM objects WHERE supersedes IS NOT NULL;") { stmt in
            while stmt.step() {
                if let sup = stmt.text(1), let id = stmt.text(0) { successor[sup] = id }
            }
        }
        // screens 스탬프의 본문에서 domain/kind/knowledge 파싱은 body(fts) 가 필요 — 스탬프 id 목록
        var stampIDs: [String] = []
        db.prepared("""
            SELECT DISTINCT c.src
            FROM cites c JOIN objects s ON s.id = c.src
            WHERE c.rel='screens'
              AND s.type='screening'
              AND s.retracts IS NULL
              AND s.id NOT IN (SELECT supersedes FROM objects WHERE supersedes IS NOT NULL)
              AND s.id NOT IN (SELECT retracts FROM objects WHERE retracts IS NOT NULL);
            """) { stmt in
            while stmt.step() { if let id = stmt.text(0) { stampIDs.append(id) } }
        }
        db.exec("BEGIN;")
        for sid in stampIDs {
            guard let body = ftsBody(sid) else { continue }
            let (domain, kind, knowledge) = LedgerObject.parseClassification(body)
            guard domain != nil || kind != nil || knowledge != nil else { continue }
            for dst in citeDsts(src: sid, rel: "screens") {
                var head = dst
                while let next = successor[head] { head = next }
                db.prepared("UPDATE objects SET domain=COALESCE(?,domain), kind=COALESCE(?,kind), knowledge=COALESCE(?,knowledge) WHERE id=?;") { s in
                    s.bind(1, domain); s.bind(2, kind); s.bind(3, knowledge); s.bind(4, head); s.step()
                }
            }
        }
        db.exec("COMMIT;")
    }

    private func ftsBody(_ id: String) -> String? {
        db.prepared("SELECT body FROM fts WHERE id=?;") { stmt in
            stmt.bind(1, id)
            return stmt.step() ? stmt.text(0) : nil
        } ?? nil
    }

    private func citeDsts(src: String, rel: String) -> [String] {
        db.prepared("SELECT dst FROM cites WHERE src=? AND rel=?;") { stmt -> [String] in
            stmt.bind(1, src); stmt.bind(2, rel)
            var out: [String] = []
            while stmt.step() { if let dst = stmt.text(0) { out.append(dst) } }
            return out
        } ?? []
    }
}
