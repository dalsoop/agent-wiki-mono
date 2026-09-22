import Foundation
import SQLite3

/// SQLite C API 얇은 래퍼 — 파생 DB(LedgerIndex·향후 LedgerGraph)가 공유하는 배관.
/// 정본이 아니라 캐시 전용이므로 실패는 조용히 무시한다(정본은 md, 언제든 재생성).
/// prepare/bind/step/finalize 보일러플레이트를 한 곳에 모아 복제(개판)를 막는다.
public final class SQLiteDB {
    let db: OpaquePointer?
    public let path: String

    public init(path: String) {
        self.path = path
        var handle: OpaquePointer?
        sqlite3_open(path, &handle)
        self.db = handle
        exec("PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL;")
    }

    deinit { sqlite3_close(db) }

    /// 결과를 안 받는 SQL 실행(DDL·PRAGMA·트랜잭션).
    public func exec(_ sql: String) { sqlite3_exec(db, sql, nil, nil, nil) }

    public var userVersion: Int { scalarInt("PRAGMA user_version;") ?? 0 }
    public func setUserVersion(_ version: Int) { exec("PRAGMA user_version=\(version);") }

    /// 단일 정수 스칼라 조회(COUNT·PRAGMA 등).
    public func scalarInt(_ sql: String) -> Int? {
        var out: Int?
        prepared(sql) { if $0.step() { out = Int($0.int(0)) } }
        return out
    }

    /// prepared statement 수명주기 헬퍼 — 준비 성공 시 body 에 Statement 를 넘기고
    /// 끝나면 반드시 finalize. 준비 실패면 body 를 부르지 않고 nil 반환.
    @discardableResult
    public func prepared<T>(_ sql: String, _ body: (Statement) -> T) -> T? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            sqlite3_finalize(stmt)
            return nil
        }
        defer { sqlite3_finalize(stmt) }
        return body(Statement(stmt))
    }
}

/// 준비된 statement 한 개의 바인드·스텝·컬럼 접근을 감싼 값. SQLiteDB.prepared 안에서만 산다.
public struct Statement {
    let stmt: OpaquePointer?
    init(_ stmt: OpaquePointer?) { self.stmt = stmt }

    // MARK: 바인드 (1-based index)
    public func bind(_ index: Int32, _ text: String?) {
        if let text { sqlite3_bind_text(stmt, index, (text as NSString).utf8String, -1, nil) }
        else { sqlite3_bind_null(stmt, index) }
    }
    public func bind(_ index: Int32, _ value: Double) { sqlite3_bind_double(stmt, index, value) }
    public func bind(_ index: Int32, _ value: Int64) { sqlite3_bind_int64(stmt, index, value) }

    /// 한 행 전진. 행이 있으면 true(SQLITE_ROW).
    @discardableResult
    public func step() -> Bool { sqlite3_step(stmt) == SQLITE_ROW }

    // MARK: 컬럼 접근 (0-based index)
    public func text(_ column: Int32) -> String? {
        sqlite3_column_text(stmt, column).map { String(cString: $0) }
    }
    public func int(_ column: Int32) -> Int64 { sqlite3_column_int64(stmt, column) }
    public func double(_ column: Int32) -> Double { sqlite3_column_double(stmt, column) }
}
