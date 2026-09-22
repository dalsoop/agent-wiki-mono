import Foundation

/// 파생 그래프 (SQLite) — 객체(md)와 사건(events)을 한 그래프로 이어 순회 질의를 뽑는다.
/// 정본은 md·events·blobs, 이 DB 는 언제든 재빌드 가능한 캐시(SPEC 제7조). state/graph.db.
/// index.db(전문검색)와 분리 — 여기는 그래프 순회(타임라인·이웃·인과) 전담.
/// SQLite 배관은 SQLiteDB 헬퍼 공유(LedgerIndex 와 같은 코드).
public final class LedgerGraph {
    private let db: SQLiteDB
    public var path: String { db.path }

    public init(root: URL) {
        let dir = root.appendingPathComponent("state")
        do { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) } catch { _ = error }
        self.db = SQLiteDB(path: dir.appendingPathComponent("graph.db").path)
        migrate()
    }

    private func migrate() {
        if db.userVersion < 1 {
            db.exec("""
            CREATE TABLE IF NOT EXISTS nodes(
                id TEXT PRIMARY KEY, kind TEXT, label TEXT, occurred TEXT
            );
            CREATE INDEX IF NOT EXISTS idx_nodes_kind ON nodes(kind);
            CREATE TABLE IF NOT EXISTS edges(
                src TEXT, rel TEXT, dst TEXT, occurred TEXT, kind TEXT
            );
            CREATE INDEX IF NOT EXISTS idx_edges_src ON edges(src);
            CREATE INDEX IF NOT EXISTS idx_edges_dst ON edges(dst);
            CREATE INDEX IF NOT EXISTS idx_edges_occurred ON edges(occurred);
            """)
            db.setUserVersion(1)
        }
    }

    // MARK: - 빌드 (md 객체 + 사건 → 그래프). 파생이라 전량 재빌드.

    /// 객체와 사건에서 그래프를 통째로 재구성. 고volume 시 증분은 후속 과제(지금은 재빌드).
    /// 간선 종류: cite(객체→객체) · observes(해석→사건) · event(사건↔주어/대상).
    public func rebuild(objects: [LedgerObject], events: [Event]) {
        db.exec("BEGIN; DELETE FROM nodes; DELETE FROM edges;")
        for o in objects {
            let occurred = LedgerObject.iso.string(from: o.published)
            insertNode(o.id, kind: "object", label: o.title, occurred: occurred)
            for cite in o.cites { insertEdge(o.id, cite.rel, cite.id, occurred, "cite") }
            for eventID in o.observes { insertEdge(o.id, "observes", eventID, occurred, "observes") }
        }
        for e in events {
            let occurred = LedgerObject.iso.string(from: e.occurred)
            insertNode(e.id, kind: "event", label: e.rel, occurred: occurred)
            insertEdge(e.id, "subject", e.subject, occurred, "event")
            if let object = e.object { insertEdge(e.id, "object", object, occurred, "event") }
        }
        db.exec("COMMIT;")
    }

    private func insertNode(_ id: String, kind: String, label: String?, occurred: String) {
        db.prepared("INSERT OR REPLACE INTO nodes(id,kind,label,occurred) VALUES(?,?,?,?);") { s in
            s.bind(1, id); s.bind(2, kind); s.bind(3, label); s.bind(4, occurred); s.step()
        }
    }

    private func insertEdge(_ src: String, _ rel: String, _ dst: String, _ occurred: String, _ kind: String) {
        db.prepared("INSERT INTO edges(src,rel,dst,occurred,kind) VALUES(?,?,?,?,?);") { s in
            s.bind(1, src); s.bind(2, rel); s.bind(3, dst); s.bind(4, occurred); s.bind(5, kind); s.step()
        }
    }

    // MARK: - 질의 (순회)

    public func counts() -> (nodes: Int, edges: Int) {
        (db.scalarInt("SELECT COUNT(*) FROM nodes;") ?? 0, db.scalarInt("SELECT COUNT(*) FROM edges;") ?? 0)
    }

    public struct TimelineRow: Sendable {
        public let eventID: String, rel: String, role: String, occurred: String
    }

    /// 엔티티/객체의 타임라인 — 그 객체를 주어(subject)나 대상(object)으로 삼은 사건들, occurred 순.
    /// "이 엔티티에 무슨 일이 있었나" — 객체 중심 ↔ 사건 중심을 잇는 핵심 질의.
    public func timeline(of objectID: String, limit: Int = 200) -> [TimelineRow] {
        db.prepared("""
        SELECT e.src, n.label, e.rel, e.occurred
        FROM edges e JOIN nodes n ON n.id = e.src
        WHERE e.kind='event' AND e.dst=?
        ORDER BY e.occurred DESC LIMIT ?;
        """) { stmt -> [TimelineRow] in
            stmt.bind(1, objectID); stmt.bind(2, Int64(limit))
            // subject·object 가 같은 객체면 한 사건이 두 간선으로 잡힌다 — eventID 로 중복 제거.
            var seen = Set<String>()
            var rows: [TimelineRow] = []
            while stmt.step() {
                let eventID = stmt.text(0) ?? ""
                guard seen.insert(eventID).inserted else { continue }
                rows.append(TimelineRow(eventID: eventID, rel: stmt.text(1) ?? "",
                                        role: stmt.text(2) ?? "", occurred: stmt.text(3) ?? ""))
            }
            return rows
        } ?? []
    }

    public struct Neighbor: Sendable {
        public let id: String, rel: String, kind: String, direction: String
    }

    /// 직접 이웃 — 나가는(out)·들어오는(in) 간선 모두. 헤어볼 대신 포커스 순회용.
    public func neighbors(of id: String, limit: Int = 200) -> [Neighbor] {
        var out: [Neighbor] = []
        db.prepared("SELECT dst, rel, kind FROM edges WHERE src=? LIMIT ?;") { stmt in
            stmt.bind(1, id); stmt.bind(2, Int64(limit))
            while stmt.step() {
                out.append(Neighbor(id: stmt.text(0) ?? "", rel: stmt.text(1) ?? "",
                                    kind: stmt.text(2) ?? "", direction: "out"))
            }
        }
        db.prepared("SELECT src, rel, kind FROM edges WHERE dst=? LIMIT ?;") { stmt in
            stmt.bind(1, id); stmt.bind(2, Int64(limit))
            while stmt.step() {
                out.append(Neighbor(id: stmt.text(0) ?? "", rel: stmt.text(1) ?? "",
                                    kind: stmt.text(2) ?? "", direction: "in"))
            }
        }
        return out
    }

    /// 이 사건을 해석한 것들 — observes 로 사건을 가리키는 해석 객체 id(경합하는 여러 판단).
    public func interpretations(of eventID: String) -> [String] {
        db.prepared("SELECT src FROM edges WHERE kind='observes' AND dst=?;") { stmt -> [String] in
            stmt.bind(1, eventID)
            var ids: [String] = []
            while stmt.step() { if let id = stmt.text(0) { ids.append(id) } }
            return ids
        } ?? []
    }
}
