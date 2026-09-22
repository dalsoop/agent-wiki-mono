import Foundation
import SQLite3
import FastDiskIOKit

/// Manages the underlying `transcripts.sqlite` storage engine using SQLite C API bindings
/// and `FastSQLiteEngine` from `FastDiskIOKit`.
public final class TranscriptDatabase: Sendable {
    public let path: String
    public let engine: FastSQLiteEngine
    private let transactionLock = NSRecursiveLock()

    /// Default database file name.
    public static let defaultFileName = "transcripts.sqlite"

    /// Opens or creates a transcript database at the designated file path.
    public init(path: String) throws {
        self.path = path

        // Ensure parent directory exists if path is not in-memory
        if path != ":memory:" && !path.hasPrefix("file::memory:") {
            let parentDir = URL(fileURLWithPath: path).deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }

        self.engine = try FastSQLiteEngine.open(path: path, readOnly: false)
        try bootstrapSchema()
    }

    /// Convenience initializer using directory URL.
    public static func defaultDatabase(at directoryURL: URL) throws -> TranscriptDatabase {
        let fileURL = directoryURL.appendingPathComponent(defaultFileName)
        return try TranscriptDatabase(path: fileURL.path)
    }

    /// Creates an ephemeral in-memory transcript database for tests or fast transient storage.
    public static func inMemory() throws -> TranscriptDatabase {
        try TranscriptDatabase(path: ":memory:")
    }

    /// Executes database schema bootstrap and enforces required performance PRAGMAs.
    private func bootstrapSchema() throws {
        transactionLock.lock()
        defer { transactionLock.unlock() }

        try configurePragmas()
        try createTables()
        try migrateColumns()
        try createIndexesAndTriggers()
    }

    private func configurePragmas() throws {
        try engine.exec(sql: "PRAGMA journal_mode = WAL;")
        try engine.exec(sql: "PRAGMA synchronous = NORMAL;")
        try engine.exec(sql: "PRAGMA mmap_size = 268435456;")
        try engine.exec(sql: "PRAGMA cache_size = -64000;")
        try engine.exec(sql: "PRAGMA busy_timeout = 5000;")
        try engine.exec(sql: "PRAGMA foreign_keys = ON;")
    }

    private func createTables() throws {
        try engine.exec(sql: """
        CREATE TABLE IF NOT EXISTS sessions (
            session_id TEXT PRIMARY KEY NOT NULL,
            agent_id TEXT NOT NULL,
            room_id TEXT,
            title TEXT NOT NULL,
            total_turns INTEGER NOT NULL DEFAULT 0,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            metadata TEXT NOT NULL DEFAULT '{}'
        );
        """)

        try engine.exec(sql: """
        CREATE TABLE IF NOT EXISTS transcript_messages (
            id TEXT PRIMARY KEY NOT NULL,
            session_id TEXT NOT NULL,
            turn_index INTEGER NOT NULL,
            role TEXT NOT NULL,
            content TEXT NOT NULL,
            token_count INTEGER NOT NULL DEFAULT 0,
            created_at REAL NOT NULL,
            metadata TEXT NOT NULL DEFAULT '{}',
            valence REAL DEFAULT 0.0,
            arousal REAL DEFAULT 0.0,
            delta_h REAL DEFAULT 0.0,
            lambda_valence REAL DEFAULT 0.0,
            lambda_arousal REAL DEFAULT 0.0,
            lambda_h REAL DEFAULT 0.0,
            FOREIGN KEY (session_id) REFERENCES sessions(session_id) ON DELETE CASCADE
        );
        """)
    }

    private func migrateColumns() throws {
        let existingColumns = try engine.query(sql: "PRAGMA table_info(transcript_messages);")
            .compactMap { $0.string(for: "name") }
        let colSet = Set(existingColumns)
        let requiredCols = ["valence", "arousal", "delta_h", "lambda_valence", "lambda_arousal", "lambda_h"]
        for col in requiredCols where !colSet.contains(col) {
            try engine.exec(sql: "ALTER TABLE transcript_messages ADD COLUMN \(col) REAL DEFAULT 0.0;")
        }
    }

    private func createIndexesAndTriggers() throws {
        try engine.exec(sql: """
        CREATE INDEX IF NOT EXISTS idx_transcript_session_turn 
        ON transcript_messages(session_id, turn_index DESC);
        """)

        try engine.exec(sql: """
        CREATE UNIQUE INDEX IF NOT EXISTS uq_transcript_session_turn 
        ON transcript_messages(session_id, turn_index);
        """)

        try engine.exec(sql: """
        CREATE INDEX IF NOT EXISTS idx_transcript_affect 
        ON transcript_messages(session_id, delta_h DESC, turn_index ASC);
        """)

        try engine.exec(sql: """
        CREATE VIRTUAL TABLE IF NOT EXISTS fts_transcript USING fts5(
            message_id UNINDEXED,
            session_id,
            role,
            content,
            tokenize = 'unicode61'
        );
        """)

        try engine.exec(sql: """
        CREATE TRIGGER IF NOT EXISTS trg_transcript_messages_ai 
        AFTER INSERT ON transcript_messages BEGIN
            INSERT INTO fts_transcript(message_id, session_id, role, content)
            VALUES (new.id, new.session_id, new.role, new.content);
        END;
        """)

        try engine.exec(sql: """
        CREATE TRIGGER IF NOT EXISTS trg_transcript_messages_ad 
        AFTER DELETE ON transcript_messages BEGIN
            DELETE FROM fts_transcript WHERE message_id = old.id;
        END;
        """)

        try engine.exec(sql: """
        CREATE TRIGGER IF NOT EXISTS trg_transcript_messages_au 
        AFTER UPDATE ON transcript_messages BEGIN
            DELETE FROM fts_transcript WHERE message_id = old.id;
            INSERT INTO fts_transcript(message_id, session_id, role, content)
            VALUES (new.id, new.session_id, new.role, new.content);
        END;
        """)
    }

    /// Executes a closure within an exclusive SQLite transaction.
    public func withTransaction<T>(_ block: () throws -> T) throws -> T {
        transactionLock.lock()
        defer { transactionLock.unlock() }

        try engine.exec(sql: "BEGIN IMMEDIATE;")
        do {
            let result = try block()
            try engine.exec(sql: "COMMIT;")
            return result
        } catch {
            do {
                try engine.exec(sql: "ROLLBACK;")
            } catch let rollbackError {
                FileHandle.standardError.write(Data("TranscriptDatabase rollback error: \(rollbackError.localizedDescription)\n".utf8))
            }
            throw error
        }
    }

    /// Executes raw SQL query without returned rows.
    public func exec(sql: String) throws {
        transactionLock.lock()
        defer { transactionLock.unlock() }
        try engine.exec(sql: sql)
    }

    /// Runs a parameterized SQL statement with bound values.
    public func run(sql: String, binds: [Any?] = []) throws {
        transactionLock.lock()
        defer { transactionLock.unlock() }
        try engine.run(sql: sql, binds: binds)
    }

    /// Queries SQLite and returns rows.
    public func query(sql: String, binds: [Any?] = []) throws -> [FastSQLiteRow] {
        transactionLock.lock()
        defer { transactionLock.unlock() }
        return try engine.query(sql: sql, binds: binds)
    }

    /// Closes the database connection.
    public func close() {
        transactionLock.lock()
        defer { transactionLock.unlock() }
        engine.close()
    }

    deinit {
        close()
    }
}
