import Foundation
import SQLite3

/// 시스템 SQLite3 에 대한 최소 read-only 접근. Antigravity 세션 저장소
/// (`conversation_summaries.db`·`conversations/<id>.db`)가 sqlite 라서
/// AgentSessionKit 의 세션 리더가 함께 쓴다. 쓰기 없음 — 원장은 각 CLI 가 소유한다.
///
/// WAL 함정(실측 2026-09-01): 열려 있는 db 는 `SQLITE_OPEN_READONLY` 로도
/// `unable to open database file` 로 실패한다. `file:…?mode=ro&immutable=1` URI 로만
/// 열리므로 일반 open 실패 시 URI 로 재시도한다. immutable 은 WAL 이 안 바뀐다는
/// 가정이지만 읽기 전용 세션 목록 용도로는 충분하다.
public final class SQLiteReadOnly {
    public enum SQLiteError: Error, CustomStringConvertible {
        case openFailed(String, String)
        case queryFailed(String, String)

        public var description: String {
            switch self {
            case .openFailed(let path, let message): return "sqlite open 실패: \(path) — \(message)"
            case .queryFailed(let sql, let message): return "sqlite query 실패: \(sql) — \(message)"
            }
        }
    }

    private var handle: OpaquePointer?
    private let path: String

    /// 데이터베이스를 읽기 전용으로 연다. 열기만 성공하면 끝이 아니라 실제 쿼리가
    /// 읽히는지 프루브로 확인한다 — WAL db 는 open 은 SQLITE_OK 여도 step 에서
    /// `unable to open database file` 로 죽는다(실측 2026-09-01).
    public init(path: String) throws {
        self.path = path
        let flags = SQLITE_OPEN_READONLY
        var db: OpaquePointer?
        if sqlite3_open_v2(path, &db, flags, nil) == SQLITE_OK, let db, Self.probe(db) {
            handle = db
            return
        }
        if let db { sqlite3_close(db) }
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(["?"])) ?? path
        let uri = "file:\(encoded)?mode=ro&immutable=1"
        guard sqlite3_open_v2(uri, &db, flags, nil) == SQLITE_OK, let db, Self.probe(db) else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            if let db { sqlite3_close(db) }
            throw SQLiteError.openFailed(path, message)
        }
        handle = db
    }

    /// open 이 실제로 읽을 수 있는 상태인가.
    private static func probe(_ db: OpaquePointer) -> Bool {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, "SELECT count(*) FROM sqlite_master", -1, &statement, nil) == SQLITE_OK
        else { return false }
        return sqlite3_step(statement) == SQLITE_ROW
    }

    deinit {
        if let handle { sqlite3_close(handle) }
    }

    public var isOpen: Bool { handle != nil }

    /// 한 쿼리의 모든 행을 순회하며 스트리밍 처리한다. 클로저가 false 를 반환하면 즉시 중단한다.
    public func forEachRow(_ sql: String, _ body: ([Column]) -> Bool) throws {
        guard let handle else { return }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteError.queryFailed(sql, String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let statement else { break }
            let count = sqlite3_column_count(statement)
            var row: [Column] = []
            row.reserveCapacity(Int(count))
            for i in 0..<count {
                row.append(Self.parseColumn(statement, at: i))
            }
            guard body(row) else { break }
        }
    }

    private static func parseColumn(_ statement: OpaquePointer, at i: Int32) -> Column {
        switch sqlite3_column_type(statement, i) {
        case SQLITE_INTEGER:
            return .int(sqlite3_column_int64(statement, i))
        case SQLITE_BLOB:
            guard let bytes = sqlite3_column_blob(statement, i) else { return .blob(Data()) }
            let count = Int(sqlite3_column_bytes(statement, i))
            return .blob(Data(bytes: bytes, count: count))
        case SQLITE_NULL:
            return .null
        default:
            guard let c = sqlite3_column_text(statement, i) else { return .null }
            return .text(String(cString: c))
        }
    }

    /// 한 쿼리의 모든 행을 문자열·정수·blob(Data) 혼합 행으로 반환한다.
    public func rows(_ sql: String) throws -> [[Column]] {
        var out: [[Column]] = []
        try forEachRow(sql) { row in
            out.append(row)
            return true
        }
        return out
    }

    public enum Column: Sendable {
        case null
        case text(String)
        case int(Int64)
        case blob(Data)

        public var text: String? {
            if case let .text(t) = self { return t }
            return nil
        }
        public var int: Int64? {
            if case let .int(v) = self { return v }
            return nil
        }
        public var blob: Data? {
            if case let .blob(d) = self { return d }
            return nil
        }
    }
}
