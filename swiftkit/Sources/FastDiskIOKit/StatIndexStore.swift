import Foundation

public struct StatIndexRecord: Sendable, Equatable {
    public let path: String
    public let inode: UInt64
    public let mtime: Date
    public let size: Int64
    public let lastOffset: Int64
    public let payload: Data?

    public init(
        path: String,
        inode: UInt64,
        mtime: Date,
        size: Int64,
        lastOffset: Int64,
        payload: Data? = nil
    ) {
        self.path = path
        self.inode = inode
        self.mtime = mtime
        self.size = size
        self.lastOffset = lastOffset
        self.payload = payload
    }
}

public final class StatIndexStore: Sendable {
    public let engine: FastSQLiteEngine

    public init(engine: FastSQLiteEngine) throws {
        self.engine = engine
        try setupTable()
    }

    public init(path: String) throws {
        self.engine = try FastSQLiteEngine.open(path: path, readOnly: false)
        try setupTable()
    }

    private func setupTable() throws {
        let sql = """
        CREATE TABLE IF NOT EXISTS file_stat_index (
            path TEXT PRIMARY KEY,
            inode INTEGER,
            mtime REAL,
            size INTEGER,
            last_offset INTEGER,
            payload BLOB
        );
        """
        try engine.exec(sql: sql)
    }

    public func isUnmodified(path: String, size: Int64, mtime: Date, inode: UInt64? = nil) -> Bool {
        do {
            let sql = "SELECT inode, size, mtime FROM file_stat_index WHERE path = ? LIMIT 1;"
            let rows = try engine.query(sql: sql, binds: [path])
            guard let row = rows.first,
                  let storedSize = row.int64(for: "size"),
                  let storedMtime = row.double(for: "mtime") else {
                return false
            }
            if let inode = inode, let storedInode = row.int64(for: "inode") {
                if UInt64(bitPattern: storedInode) != inode {
                    return false
                }
            }
            let diff = abs(storedMtime - mtime.timeIntervalSince1970)
            return storedSize == size && diff < 0.001
        } catch {
            return false
        }
    }

    public func update(
        path: String,
        inode: UInt64,
        size: Int64,
        mtime: Date,
        lastOffset: Int64,
        payload: Data? = nil
    ) {
        do {
            try updateThrowing(
                path: path,
                inode: inode,
                size: size,
                mtime: mtime,
                lastOffset: lastOffset,
                payload: payload
            )
        } catch {
            // Ignored in non-throwing interface
        }
    }

    public func updateThrowing(
        path: String,
        inode: UInt64,
        size: Int64,
        mtime: Date,
        lastOffset: Int64,
        payload: Data? = nil
    ) throws {
        let sql = """
        INSERT INTO file_stat_index (path, inode, mtime, size, last_offset, payload)
        VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT(path) DO UPDATE SET
            inode = excluded.inode,
            mtime = excluded.mtime,
            size = excluded.size,
            last_offset = excluded.last_offset,
            payload = excluded.payload;
        """
        try engine.run(sql: sql, binds: [
            path,
            Int64(bitPattern: inode),
            mtime.timeIntervalSince1970,
            size,
            lastOffset,
            payload
        ])
    }

    public func get(path: String) -> StatIndexRecord? {
        do {
            let sql = "SELECT path, inode, mtime, size, last_offset, payload FROM file_stat_index WHERE path = ? LIMIT 1;"
            let rows = try engine.query(sql: sql, binds: [path])
            guard let row = rows.first,
                  let p = row.string(for: "path"),
                  let ino = row.int64(for: "inode"),
                  let mt = row.double(for: "mtime"),
                  let sz = row.int64(for: "size"),
                  let off = row.int64(for: "last_offset") else {
                return nil
            }
            let date = Date(timeIntervalSince1970: mt)
            let payload = row.data(for: "payload")
            return StatIndexRecord(
                path: p,
                inode: UInt64(bitPattern: ino),
                mtime: date,
                size: sz,
                lastOffset: off,
                payload: payload
            )
        } catch {
            return nil
        }
    }
}
