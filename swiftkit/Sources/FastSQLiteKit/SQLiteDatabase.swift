import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
#if canImport(SQLite3)
import SQLite3
#endif

public enum SQLiteError: LocalizedError, Sendable {
    case openFailed(String)
    case executionFailed(String, code: Int32)
    case statementFailed(String, code: Int32)
    case migrationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .openFailed(let msg): return "SQLite DB 열기 실패: \(msg)"
        case .executionFailed(let sql, let code): return "SQL 실행 실패 (code: \(code)): \(sql)"
        case .statementFailed(let msg, let code): return "Prepared Statement 실패 (code: \(code)): \(msg)"
        case .migrationFailed(let msg): return "마이그레이션 실패: \(msg)"
        }
    }
}

/// 고성능 임베디드 SQLite 데이터베이스 SSOT 연결 래퍼.
/// WAL 모드, busy_timeout(5초), 직렬화/멀티스레드 안전 플래그가 기본 적용됩니다.
public final class SQLiteDatabase: @unchecked Sendable {
    private var rawHandle: OpaquePointer?
    private let lock = NSLock()

    public var handle: OpaquePointer? {
        lock.lock()
        defer { lock.unlock() }
        return rawHandle
    }

    public init(url: URL, readOnly: Bool = false) throws {
        let flags = readOnly
            ? (SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX)
            : (SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX)

        var db: OpaquePointer?
        let rc = sqlite3_open_v2(url.path, &db, flags, nil)
        guard rc == SQLITE_OK, let db else {
            let msg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            if let db { sqlite3_close(db) }
            throw SQLiteError.openFailed(msg)
        }
        self.rawHandle = db

        // 성능 및 동시성 안정성 기본 설정
        try execute("PRAGMA journal_mode=WAL;")
        try execute("PRAGMA busy_timeout=5000;")
        try execute("PRAGMA foreign_keys=ON;")
    }

    /// 인메모리 임시 데이터베이스 생성 (테스트용)
    public init() throws {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_MEMORY | SQLITE_OPEN_FULLMUTEX
        let rc = sqlite3_open_v2(":memory:", &db, flags, nil)
        guard rc == SQLITE_OK, let db else {
            let msg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            if let db { sqlite3_close(db) }
            throw SQLiteError.openFailed(msg)
        }
        self.rawHandle = db
        try execute("PRAGMA foreign_keys=ON;")
    }

    deinit {
        close()
    }

    public func close() {
        lock.lock()
        defer { lock.unlock() }
        if let db = rawHandle {
            sqlite3_close(db)
            rawHandle = nil
        }
    }

    public func execute(_ sql: String) throws {
        lock.lock()
        defer { lock.unlock() }
        guard let db = rawHandle else {
            throw SQLiteError.executionFailed("DB가 이미 닫혀 있습니다", code: -1)
        }

        var errMsg: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &errMsg)
        if rc != SQLITE_OK {
            let msg = errMsg.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(db))
            sqlite3_free(errMsg)
            throw SQLiteError.executionFailed(msg, code: rc)
        }
    }

    public func userVersion() throws -> Int {
        lock.lock()
        defer { lock.unlock() }
        guard let db = rawHandle else {
            throw SQLiteError.executionFailed("DB가 이미 닫혀 있습니다", code: -1)
        }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA user_version;", -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw SQLiteError.statementFailed(String(cString: sqlite3_errmsg(db)), code: -1)
        }
        defer { sqlite3_finalize(stmt) }

        if sqlite3_step(stmt) == SQLITE_ROW {
            return Int(sqlite3_column_int(stmt, 0))
        }
        return 0
    }

    public func setUserVersion(_ version: Int) throws {
        try execute("PRAGMA user_version = \(version);")
    }

    public func inTransaction<T>(_ block: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE TRANSACTION;")
        do {
            let result = try block()
            try execute("COMMIT;")
            return result
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }
}
