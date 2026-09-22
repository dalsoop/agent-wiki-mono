import Foundation
#if os(macOS)
import SQLite3
#endif

/// Gujo 앱 영속 저장 정본.
///
/// 설정·작업은 `~/Library/Application Support/<bundleId>/app.sqlite` 한 파일이다.
/// `~/.swift-app-state` 는 관측 미러라 여기에 두지 않는다.
public enum DurableAppLayout: Sendable {
    public static let sqliteFileName = "app.sqlite"
    public static let bundleIDPrefix = "net.ranode."

    public static func bundleID(slug: String) -> String {
        let slug = slug.trimmingCharacters(in: .whitespacesAndNewlines)
        if slug.hasPrefix("net.ranode.") || slug.hasPrefix("ai.gujo.") { return slug }
        return bundleIDPrefix + slug
    }

    #if os(macOS)
    public static var defaultHomeDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
    }
    #else
    public static var defaultHomeDirectory: URL {
        URL(fileURLWithPath: NSHomeDirectory())
    }
    #endif

    public static func supportRoot(
        slug: String,
        home: URL = defaultHomeDirectory
    ) -> URL {
        home
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(bundleID(slug: slug), isDirectory: true)
    }

    public static func sqliteURL(
        slug: String,
        home: URL = defaultHomeDirectory
    ) -> URL {
        supportRoot(slug: slug, home: home).appendingPathComponent(sqliteFileName, isDirectory: false)
    }

    public static func tildePath(_ url: URL, home: URL = defaultHomeDirectory) -> String {
        let path = url.path
        let prefix = home.path
        if path == prefix { return "~" }
        if path.hasPrefix(prefix + "/") {
            return "~" + String(path.dropFirst(prefix.count))
        }
        return path
    }

    public static func expandTilde(_ path: String, home: URL = defaultHomeDirectory) -> URL {
        if path == "~" { return home }
        if path.hasPrefix("~/") {
            return home.appendingPathComponent(String(path.dropFirst(2)))
        }
        return URL(fileURLWithPath: path)
    }

#if os(macOS)
    /// 빈 DB라도 만들어 두면 AppSaves 가 경로를 거둔다.
    public static func ensureDatabase(at url: URL, schemaSQL: String? = nil) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var db: OpaquePointer?
        let status = sqlite3_open_v2(
            url.path,
            &db,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE,
            nil
        )
        defer { sqlite3_close(db) }
        guard status == SQLITE_OK else {
            throw DurableStoreError.openFailed(status)
        }
        let pragmaSQL = "PRAGMA journal_mode = WAL; PRAGMA busy_timeout = 5000; PRAGMA synchronous = NORMAL;"
        var pragmaErr: UnsafeMutablePointer<CChar>?
        let pragmaExec = sqlite3_exec(db, pragmaSQL, nil, nil, &pragmaErr)
        if let pragmaErr {
            let message = String(cString: pragmaErr)
            sqlite3_free(pragmaErr)
            throw DurableStoreError.execFailed(message)
        }
        guard pragmaExec == SQLITE_OK else {
            throw DurableStoreError.execFailed("sqlite3_exec \(pragmaExec)")
        }
        let sql = schemaSQL ?? """
        CREATE TABLE IF NOT EXISTS app_kv (
            namespace TEXT NOT NULL,
            key TEXT NOT NULL,
            value TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            PRIMARY KEY (namespace, key)
        );
        """
        var err: UnsafeMutablePointer<CChar>?
        let exec = sqlite3_exec(db, sql, nil, nil, &err)
        if let err {
            let message = String(cString: err)
            sqlite3_free(err)
            throw DurableStoreError.execFailed(message)
        }
        guard exec == SQLITE_OK else {
            throw DurableStoreError.execFailed("sqlite3_exec \(exec)")
        }
    }
#endif // Linux: sqlite C 모듈 미매핑(실측 2026-08-29)
}

public enum DurableStoreError: Error, Equatable, LocalizedError, Sendable {
    case openFailed(Int32)
    case execFailed(String)

    public var errorDescription: String? {
        switch self {
        case .openFailed(let code): return "sqlite open failed (\(code))"
        case .execFailed(let message): return message
        }
    }
}
