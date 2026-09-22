import Foundation
#if canImport(SQLite3)
import SQLite3
#endif

public enum FastSQLiteError: Error, LocalizedError, Sendable {
    case openFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
    case bindFailed(String)
    case executionFailed(String)
    case databaseClosed

    public var errorDescription: String? {
        switch self {
        case .openFailed(let msg): return "SQLite open failed: \(msg)"
        case .prepareFailed(let msg): return "SQLite prepare failed: \(msg)"
        case .stepFailed(let msg): return "SQLite step failed: \(msg)"
        case .bindFailed(let msg): return "SQLite bind failed: \(msg)"
        case .executionFailed(let msg): return "SQLite exec failed: \(msg)"
        case .databaseClosed: return "SQLite database is closed"
        }
    }
}

public enum FastSQLiteValue: Sendable, Equatable {
    case integer(Int64)
    case real(Double)
    case text(String)
    case blob(Data)
    case null

    public var int64Value: Int64? {
        switch self {
        case .integer(let v): return v
        case .real(let v): return Int64(v)
        case .text(let v): return Int64(v)
        case .blob, .null: return nil
        }
    }

    public var intValue: Int? {
        int64Value.map(Int.init)
    }

    public var doubleValue: Double? {
        switch self {
        case .real(let v): return v
        case .integer(let v): return Double(v)
        case .text(let v): return Double(v)
        case .blob, .null: return nil
        }
    }

    public var stringValue: String? {
        switch self {
        case .text(let v): return v
        case .integer(let v): return String(v)
        case .real(let v): return String(v)
        case .blob(let d): return String(data: d, encoding: .utf8)
        case .null: return nil
        }
    }

    public var dataValue: Data? {
        switch self {
        case .blob(let d): return d
        case .text(let s): return s.data(using: .utf8)
        case .integer, .real, .null: return nil
        }
    }

    public var isNull: Bool {
        if case .null = self { return true }
        return false
    }
}

public struct FastSQLiteRow: Sendable {
    public let columns: [String]
    public let values: [FastSQLiteValue]
    private let indexMap: [String: Int]

    public init(columns: [String], values: [FastSQLiteValue]) {
        self.columns = columns
        self.values = values
        var map = [String: Int]()
        map.reserveCapacity(columns.count)
        for (i, c) in columns.enumerated() {
            map[c] = i
        }
        self.indexMap = map
    }

    public subscript(index: Int) -> FastSQLiteValue {
        values[index]
    }

    public subscript(column: String) -> FastSQLiteValue? {
        guard let idx = indexMap[column] else { return nil }
        return values[idx]
    }

    public func int64(for column: String) -> Int64? {
        self[column]?.int64Value
    }

    public func int(for column: String) -> Int? {
        self[column]?.intValue
    }

    public func double(for column: String) -> Double? {
        self[column]?.doubleValue
    }

    public func string(for column: String) -> String? {
        self[column]?.stringValue
    }

    public func data(for column: String) -> Data? {
        self[column]?.dataValue
    }

    public var asDictionary: [String: Any] {
        var dict = [String: Any]()
        for (i, c) in columns.enumerated() {
            switch values[i] {
            case .integer(let v): dict[c] = v
            case .real(let v): dict[c] = v
            case .text(let v): dict[c] = v
            case .blob(let v): dict[c] = v
            case .null: dict[c] = NSNull()
            }
        }
        return dict
    }
}

#if canImport(SQLite3)
public final class FastSQLiteEngine: @unchecked Sendable {
    private var db: OpaquePointer?
    private let lock = NSLock()
    public let path: String
    public let isReadOnly: Bool

    public static func open(path: String, readOnly: Bool = false) throws -> FastSQLiteEngine {
        try FastSQLiteEngine(path: path, readOnly: readOnly)
    }

    private static let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private static func probe(_ db: OpaquePointer) -> Bool {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, "SELECT count(*) FROM sqlite_master LIMIT 1;", -1, &statement, nil) == SQLITE_OK else {
            return false
        }
        return sqlite3_step(statement) == SQLITE_ROW
    }

    public init(path: String, readOnly: Bool = false) throws {
        self.path = path
        self.isReadOnly = readOnly

        var handle: OpaquePointer?
        if !readOnly {
            let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
            let rc = sqlite3_open_v2(path, &handle, flags, nil)
            guard rc == SQLITE_OK, let validHandle = handle else {
                let msg = handle != nil ? String(cString: sqlite3_errmsg(handle!)) : "open failed with code \(rc)"
                if let handle { sqlite3_close_v2(handle) }
                throw FastSQLiteError.openFailed(msg)
            }
            self.db = validHandle

            // Enforce pragmas
            sqlite3_exec(validHandle, "PRAGMA journal_mode = WAL;", nil, nil, nil)
            sqlite3_exec(validHandle, "PRAGMA synchronous = NORMAL;", nil, nil, nil)
            sqlite3_exec(validHandle, "PRAGMA busy_timeout = 5000;", nil, nil, nil)
            sqlite3_exec(validHandle, "PRAGMA mmap_size = 268435456;", nil, nil, nil)
        } else {
            let flags = SQLITE_OPEN_READONLY
            var rc = sqlite3_open_v2(path, &handle, flags, nil)
            let openedAndReadable = (rc == SQLITE_OK && handle != nil && Self.probe(handle!))

            if !openedAndReadable {
                if let handle { sqlite3_close_v2(handle) }
                handle = nil
                // Fallback to mode=ro&immutable=1 URI with RFC 3986 percent encoding
                let uri: String
                if path.hasPrefix("file:") {
                    uri = path.contains("?") ? "\(path)&mode=ro&immutable=1" : "\(path)?mode=ro&immutable=1"
                } else {
                    let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(["?"])) ?? path
                    uri = "file:\(encodedPath)?mode=ro&immutable=1"
                }
                rc = sqlite3_open_v2(uri, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil)
            }

            guard rc == SQLITE_OK, let validHandle = handle, Self.probe(validHandle) else {
                let msg = handle != nil ? String(cString: sqlite3_errmsg(handle!)) : "read-only open failed with code \(rc)"
                if let handle { sqlite3_close_v2(handle) }
                throw FastSQLiteError.openFailed(msg)
            }
            self.db = validHandle

            sqlite3_exec(validHandle, "PRAGMA busy_timeout = 5000;", nil, nil, nil)
            sqlite3_exec(validHandle, "PRAGMA mmap_size = 268435456;", nil, nil, nil)
        }
    }

    public func exec(sql: String) throws {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { throw FastSQLiteError.databaseClosed }

        var errMsg: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &errMsg)
        if rc != SQLITE_OK {
            let msg = errMsg != nil ? String(cString: errMsg!) : String(cString: sqlite3_errmsg(db))
            sqlite3_free(errMsg)
            throw FastSQLiteError.executionFailed(msg)
        }
    }

    public func run(sql: String, binds: [Any?] = []) throws {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { throw FastSQLiteError.databaseClosed }

        var stmt: OpaquePointer?
        let prepRc = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard prepRc == SQLITE_OK, let validStmt = stmt else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw FastSQLiteError.prepareFailed(msg)
        }
        defer { sqlite3_finalize(validStmt) }

        try bindValues(stmt: validStmt, binds: binds)

        let stepRc = sqlite3_step(validStmt)
        if stepRc != SQLITE_DONE && stepRc != SQLITE_ROW {
            let msg = String(cString: sqlite3_errmsg(db))
            throw FastSQLiteError.stepFailed(msg)
        }
    }

    public func query(sql: String, binds: [Any?] = []) throws -> [FastSQLiteRow] {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { throw FastSQLiteError.databaseClosed }

        var stmt: OpaquePointer?
        let prepRc = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard prepRc == SQLITE_OK, let validStmt = stmt else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw FastSQLiteError.prepareFailed(msg)
        }
        defer { sqlite3_finalize(validStmt) }

        try bindValues(stmt: validStmt, binds: binds)

        let colCount = Int(sqlite3_column_count(validStmt))
        var columns = [String]()
        columns.reserveCapacity(colCount)
        for i in 0..<colCount {
            if let cName = sqlite3_column_name(validStmt, Int32(i)) {
                columns.append(String(cString: cName))
            } else {
                columns.append("col_\(i)")
            }
        }

        var rows = [FastSQLiteRow]()
        while true {
            let stepRc = sqlite3_step(validStmt)
            if stepRc == SQLITE_DONE {
                break
            }
            if stepRc != SQLITE_ROW {
                let msg = String(cString: sqlite3_errmsg(db))
                throw FastSQLiteError.stepFailed(msg)
            }

            var values = [FastSQLiteValue]()
            values.reserveCapacity(colCount)

            for i in 0..<colCount {
                let idx = Int32(i)
                let type = sqlite3_column_type(validStmt, idx)
                switch type {
                case SQLITE_INTEGER:
                    let val = sqlite3_column_int64(validStmt, idx)
                    values.append(.integer(val))
                case SQLITE_FLOAT:
                    let val = sqlite3_column_double(validStmt, idx)
                    values.append(.real(val))
                case SQLITE_TEXT:
                    if let textPtr = sqlite3_column_text(validStmt, idx) {
                        values.append(.text(String(cString: textPtr)))
                    } else {
                        values.append(.text(""))
                    }
                case SQLITE_BLOB:
                    if let blobPtr = sqlite3_column_blob(validStmt, idx) {
                        let count = Int(sqlite3_column_bytes(validStmt, idx))
                        values.append(.blob(Data(bytes: blobPtr, count: count)))
                    } else {
                        values.append(.blob(Data()))
                    }
                case SQLITE_NULL:
                    values.append(.null)
                default:
                    values.append(.null)
                }
            }
            rows.append(FastSQLiteRow(columns: columns, values: values))
        }

        return rows
    }

    private func bindValues(stmt: OpaquePointer, binds: [Any?]) throws {
        for (index, val) in binds.enumerated() {
            let col = Int32(index + 1)
            let rc: Int32
            switch val {
            case nil:
                rc = sqlite3_bind_null(stmt, col)
            case is NSNull:
                rc = sqlite3_bind_null(stmt, col)
            case let i as Int64:
                rc = sqlite3_bind_int64(stmt, col, i)
            case let i as Int:
                rc = sqlite3_bind_int64(stmt, col, Int64(i))
            case let i as Int32:
                rc = sqlite3_bind_int(stmt, col, i)
            case let u as UInt64:
                rc = sqlite3_bind_int64(stmt, col, Int64(bitPattern: u))
            case let u as UInt:
                rc = sqlite3_bind_int64(stmt, col, Int64(u))
            case let d as Double:
                rc = sqlite3_bind_double(stmt, col, d)
            case let f as Float:
                rc = sqlite3_bind_double(stmt, col, Double(f))
            case let s as String:
                rc = sqlite3_bind_text(stmt, col, s, -1, Self.SQLITE_TRANSIENT)
            case let d as Date:
                rc = sqlite3_bind_double(stmt, col, d.timeIntervalSince1970)
            case let data as Data:
                rc = data.withUnsafeBytes { rawPtr in
                    sqlite3_bind_blob(stmt, col, rawPtr.baseAddress, Int32(data.count), Self.SQLITE_TRANSIENT)
                }
            case let sqliteVal as FastSQLiteValue:
                switch sqliteVal {
                case .integer(let v): rc = sqlite3_bind_int64(stmt, col, v)
                case .real(let v): rc = sqlite3_bind_double(stmt, col, v)
                case .text(let v): rc = sqlite3_bind_text(stmt, col, v, -1, Self.SQLITE_TRANSIENT)
                case .blob(let v):
                    rc = v.withUnsafeBytes { rawPtr in
                        sqlite3_bind_blob(stmt, col, rawPtr.baseAddress, Int32(v.count), Self.SQLITE_TRANSIENT)
                    }
                case .null: rc = sqlite3_bind_null(stmt, col)
                }
            default:
                let s = "\(val!)"
                rc = sqlite3_bind_text(stmt, col, s, -1, Self.SQLITE_TRANSIENT)
            }

            if rc != SQLITE_OK {
                throw FastSQLiteError.bindFailed("Failed to bind argument at index \(index + 1)")
            }
        }
    }

    public func close() {
        lock.lock()
        defer { lock.unlock() }
        if let db {
            sqlite3_close_v2(db)
            self.db = nil
        }
    }

    deinit {
        close()
    }
}

#else
public final class FastSQLiteEngine: Sendable {
    public let path: String
    public let isReadOnly: Bool

    public static func open(path: String, readOnly: Bool = false) throws -> FastSQLiteEngine {
        throw FastSQLiteError.openFailed("SQLite3 is unavailable on this platform")
    }

    public init(path: String, readOnly: Bool = false) throws {
        self.path = path
        self.isReadOnly = readOnly
        throw FastSQLiteError.openFailed("SQLite3 is unavailable on this platform")
    }

    public func exec(sql: String) throws {
        throw FastSQLiteError.executionFailed("SQLite3 is unavailable on this platform")
    }

    public func run(sql: String, binds: [Any?] = []) throws {
        throw FastSQLiteError.executionFailed("SQLite3 is unavailable on this platform")
    }

    public func query(sql: String, binds: [Any?] = []) throws -> [FastSQLiteRow] {
        throw FastSQLiteError.executionFailed("SQLite3 is unavailable on this platform")
    }

    public func close() {}
}
#endif
