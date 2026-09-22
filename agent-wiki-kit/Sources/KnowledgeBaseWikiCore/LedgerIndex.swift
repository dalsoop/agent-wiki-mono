import Foundation

/// 파생 인덱스 (SQLite) — md 가 정본, 이 DB 는 언제든 삭제·재생성 가능한 캐시다(SPEC 제7조).
/// 100만 객체에서 전량 파일 스캔·전 본문 상주를 피하려는 목적. 정본은 절대 여기에 없다.
/// 저장 위치: <root>/state/index.db (objects/ 밖 — 정본과 분리).
/// SQLite 배관은 SQLiteDB 헬퍼로 공유 — LedgerGraph 등 다른 파생 DB 와 같은 코드를 쓴다.
public final class LedgerIndex {
    let db: SQLiteDB
    public var path: String { db.path }

    public init(root: URL) {
        let dir = root.appendingPathComponent("state")
        do { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) } catch { _ = error }
        self.db = SQLiteDB(path: dir.appendingPathComponent("index.db").path)
        migrate()
    }

    private func migrate() {
        if db.userVersion < 1 {
            db.exec("""
            CREATE TABLE IF NOT EXISTS objects(
                id TEXT PRIMARY KEY, title TEXT, type TEXT, author TEXT,
                published TEXT, tags TEXT, origin TEXT, batch TEXT,
                supersedes TEXT, retracts TEXT, sha256 TEXT,
                mtime REAL, size INTEGER,
                domain TEXT, kind TEXT, knowledge TEXT
            );
            CREATE INDEX IF NOT EXISTS idx_type ON objects(type);
            CREATE INDEX IF NOT EXISTS idx_supersedes ON objects(supersedes);
            CREATE INDEX IF NOT EXISTS idx_retracts ON objects(retracts);
            CREATE TABLE IF NOT EXISTS cites(src TEXT, dst TEXT, rel TEXT);
            CREATE INDEX IF NOT EXISTS idx_cites_dst ON cites(dst);
            CREATE INDEX IF NOT EXISTS idx_cites_src ON cites(src);
            CREATE VIRTUAL TABLE IF NOT EXISTS fts USING fts5(id UNINDEXED, title, body, tags);
            CREATE TABLE IF NOT EXISTS files(path TEXT PRIMARY KEY, id TEXT, mtime REAL, size INTEGER);
            """)
            db.setUserVersion(1)
        }
        if db.userVersion < 2 {
            // 원본층 색인 — 텍스트 blob 의 **내용**을 fts 에 넣어 검색이 원문에 닿게 한다.
            // 봉인만 하고 색인을 안 하면 "저장은 됐는데 아무도 못 찾는" 상태가 된다.
            // fts 행의 id 는 blob sha 이고, 이 표가 sha → (크기·종류·mtime) 를 들고 있다.
            db.exec("""
            CREATE TABLE IF NOT EXISTS blobs(
                sha TEXT PRIMARY KEY, size INTEGER, kind TEXT, mtime REAL
            );
            """)
            db.setUserVersion(2)
        }
        if db.userVersion < 3 {
            // 객체 → 원본 역참조. 두 경로를 **같은 표에** 모은다:
            //   typed — `source.blob` 필드 (수집물의 정식 provenance, 객체당 하나)
            //   body  — 본문에 적힌 64자 sha (그림 여러 장을 안은 문서가 쓰는 형태)
            //
            // 본문 참조를 색인하지 않던 게 `blob gc` 가 산 원본을 회수 대상으로 보던
            // 원인이었다. 데이터를 고쳐 쓰는 대신(append-only 라 supersede 40건이 든다)
            // **읽는 쪽을 가르친다** — 64자 hex 는 모호하지 않고, 실재하는 blob 집합과
            // 대조하므로 오탐이 없다. 그리고 `source.blob` 은 단수라 그림 여러 장을
            // 안은 문서(실측 13건)를 애초에 담지 못한다.
            db.exec("""
            CREATE TABLE IF NOT EXISTS blobrefs(
                object TEXT, sha TEXT, via TEXT
            );
            CREATE INDEX IF NOT EXISTS idx_blobrefs_sha ON blobrefs(sha);
            CREATE INDEX IF NOT EXISTS idx_blobrefs_object ON blobrefs(object);
            """)
            db.setUserVersion(3)
        }
    }

    /// 색인에 넣을 텍스트 blob 크기 상한. 원문 검색이 목적이지 전문 아카이브가 아니라,
    /// 거대한 로그 하나가 fts 를 통째로 먹는 걸 막는다. 넘으면 앞부분만 넣는다.
    static let blobTextIndexLimit = 2 * 1024 * 1024

    public func objectCount() -> Int { db.scalarInt("SELECT COUNT(*) FROM objects;") ?? 0 }

    /// FTS 행 수 — 색인 도달 범위 측정용(구조 진단). objects 수와 벌어지면 검색이 샌다.
    public func ftsRowCount() -> Int { db.scalarInt("SELECT COUNT(*) FROM fts;") ?? 0 }

    /// 이 id 가 FTS 에 있나. blob sha 를 넣어 "원문이 검색에 닿는가"를 재는 데 쓴다 —
    /// 지금은 blob 색인 경로가 없어 항상 거짓이지만, 생기면 저절로 참이 된다.
    public func ftsContains(id: String) -> Bool {
        (db.prepared("SELECT 1 FROM fts WHERE id=? LIMIT 1;") { stmt -> Int in
            stmt.bind(1, id); return stmt.step() ? 1 : 0
        } ?? 0) == 1
    }


    public struct BlobRef: Sendable {
        public let object: String
        public let via: String        // "typed" | "body"
        public let title: String?
    }

    public struct BlobHit: Sendable {
        public let sha: String
        public let size: Int
        public let kind: String
        public let snippet: String
    }

    public struct Row: Sendable {
        public let id: String, title: String?, type: String?, author: String
        public let domain: String?, kind: String?, knowledge: String?
    }

    public struct HeadRow: Sendable {
        public let id: String, title: String?, author: String
        public let published: String, supersedes: String?, retracts: String?, batch: String?
    }

    public struct Stat: Sendable, Equatable {
        public let mtime: Double
        public let size: Int
    }

    public struct Citer: Sendable { public let id: String; public let title: String?; public let author: String; public let rels: String }
}
