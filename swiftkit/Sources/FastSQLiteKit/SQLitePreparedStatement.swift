import Foundation
#if canImport(SQLite3)
import SQLite3
#endif

/// SQLite 컴파일된 쿼리 Statement 래퍼.
public final class SQLitePreparedStatement {
    private let db: SQLiteDatabase
    private var stmt: OpaquePointer?

    public init(database: SQLiteDatabase, query: String) throws {
        self.db = database
        guard let rawDB = database.handle else {
            throw SQLiteError.executionFailed("DB 핸들이 닫혀 있습니다", code: -1)
        }

        var statement: OpaquePointer?
        let rc = sqlite3_prepare_v2(rawDB, query, -1, &statement, nil)
        guard rc == SQLITE_OK, let statement else {
            let msg = String(cString: sqlite3_errmsg(rawDB))
            throw SQLiteError.statementFailed(msg, code: rc)
        }
        self.stmt = statement
    }

    deinit {
        if let stmt {
            sqlite3_finalize(stmt)
        }
    }

    public func bindText(_ value: String, at index: Int32) throws {
        guard let stmt else { return }
        let rc = sqlite3_bind_text(stmt, index, value, -1, SQLITE_TRANSIENT)
        if rc != SQLITE_OK {
            throw SQLiteError.statementFailed("bindText 실패", code: rc)
        }
    }

    public func bindInt64(_ value: Int64, at index: Int32) throws {
        guard let stmt else { return }
        let rc = sqlite3_bind_int64(stmt, index, value)
        if rc != SQLITE_OK {
            throw SQLiteError.statementFailed("bindInt64 실패", code: rc)
        }
    }

    public func bindDouble(_ value: Double, at index: Int32) throws {
        guard let stmt else { return }
        let rc = sqlite3_bind_double(stmt, index, value)
        if rc != SQLITE_OK {
            throw SQLiteError.statementFailed("bindDouble 실패", code: rc)
        }
    }

    public func bindBlob(_ data: Data, at index: Int32) throws {
        guard let stmt else { return }
        let rc = data.withUnsafeBytes { rawBuffer in
            sqlite3_bind_blob(stmt, index, rawBuffer.baseAddress, Int32(rawBuffer.count), SQLITE_TRANSIENT)
        }
        if rc != SQLITE_OK {
            throw SQLiteError.statementFailed("bindBlob 실패", code: rc)
        }
    }

    public func bindNull(at index: Int32) throws {
        guard let stmt else { return }
        let rc = sqlite3_bind_null(stmt, index)
        if rc != SQLITE_OK {
            throw SQLiteError.statementFailed("bindNull 실패", code: rc)
        }
    }

    /// 행이 있으면 true, 끝났으면 false 반환
    public func step() throws -> Bool {
        guard let stmt else { return false }
        let rc = sqlite3_step(stmt)
        switch rc {
        case SQLITE_ROW:
            return true
        case SQLITE_DONE:
            return false
        default:
            throw SQLiteError.statementFailed("step 실패", code: rc)
        }
    }

    public func reset() throws {
        guard let stmt else { return }
        sqlite3_reset(stmt)
        sqlite3_clear_bindings(stmt)
    }

    public func columnText(at index: Int32) -> String? {
        guard let stmt, let cStr = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: cStr)
    }

    public func columnInt64(at index: Int32) -> Int64 {
        guard let stmt else { return 0 }
        return sqlite3_column_int64(stmt, index)
    }

    public func columnDouble(at index: Int32) -> Double {
        guard let stmt else { return 0.0 }
        return sqlite3_column_double(stmt, index)
    }

    public func columnBlob(at index: Int32) -> Data? {
        guard let stmt, let bytes = sqlite3_column_blob(stmt, index) else { return nil }
        let count = Int(sqlite3_column_bytes(stmt, index))
        return Data(bytes: bytes, count: count)
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
