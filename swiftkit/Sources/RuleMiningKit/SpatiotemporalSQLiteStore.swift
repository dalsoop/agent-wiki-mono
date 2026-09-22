import Foundation
import SQLite3

// MARK: - 1. 도메인 모델 정의

public enum EntityType: String, Sendable, Codable {
    case symbol
    case intent
    case rule
    case ast
}

public struct SpatiotemporalCoordinate: Sendable, Codable, Equatable {
    public let coordID: String
    public let valence: Double           // -1.0 ... 1.0 (X축: 항상성 방향)
    public let arousal: Double           // 0.0 ... 1.0 (Y축: 충격/에너지)
    public let absoluteTimeSec: Double   // 단조 증가 절대 물리 시간 (Z축)
    public let homeostaticDelta: Double  // Δ Homeostasis
    public let createdAt: Double

    public init(
        coordID: String = UUID().uuidString,
        valence: Double,
        arousal: Double,
        absoluteTimeSec: Double = ProcessInfo.processInfo.systemUptime,
        homeostaticDelta: Double = 0.0,
        createdAt: Double = Date().timeIntervalSince1970
    ) {
        self.coordID = coordID
        self.valence = max(-1.0, min(1.0, valence))
        self.arousal = max(0.0, min(1.0, arousal))
        self.absoluteTimeSec = absoluteTimeSec
        self.homeostaticDelta = homeostaticDelta
        self.createdAt = createdAt
    }
}

public struct SemanticEntity: Sendable, Codable, Equatable {
    public let entityID: String
    public let entityType: EntityType
    public let rawText: String
    public let lexicalHash: String
    public let createdAt: Double

    public init(
        entityID: String = UUID().uuidString,
        entityType: EntityType,
        rawText: String,
        lexicalHash: String? = nil,
        createdAt: Double = Date().timeIntervalSince1970
    ) {
        self.entityID = entityID
        self.entityType = entityType
        self.rawText = rawText
        self.lexicalHash = lexicalHash ?? Self.hash(text: rawText)
        self.createdAt = createdAt
    }

    private static func hash(text: String) -> String {
        var hash: UInt64 = 5381
        for byte in text.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        return String(format: "%016llx", hash)
    }
}

// MARK: - 2. SQLite3 초고속 물리 스토리지 액터

public actor SpatiotemporalSQLiteStore {
    private final class DatabaseHandle {
        let rawPointer: OpaquePointer
        init(_ rawPointer: OpaquePointer) { self.rawPointer = rawPointer }
        deinit { sqlite3_close_v2(rawPointer) }
    }

    private let handle: DatabaseHandle
    private var db: OpaquePointer { handle.rawPointer }
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    public init(databaseURL: URL) throws {
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var rawDB: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databaseURL.path, &rawDB, flags, nil) == SQLITE_OK,
              let validDB = rawDB else {
            let errmsg = rawDB.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown error"
            if let rawDB { sqlite3_close(rawDB) }
            throw NSError(domain: "SpatiotemporalSQLiteStore", code: 1, userInfo: [NSLocalizedDescriptionKey: errmsg])
        }

        self.handle = DatabaseHandle(validDB)

        try Self.executeRaw(validDB, sql: "PRAGMA journal_mode = WAL;")
        try Self.executeRaw(validDB, sql: "PRAGMA synchronous = NORMAL;")
        try Self.executeRaw(validDB, sql: "PRAGMA temp_store = MEMORY;")
        try Self.executeRaw(validDB, sql: "PRAGMA foreign_keys = ON;")
        try Self.executeRaw(validDB, sql: "PRAGMA busy_timeout = 5000;")

        try Self.bootstrapSchemaRaw(validDB)
    }

    private static func executeRaw(_ database: OpaquePointer, sql: String) throws {
        var errmsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(database, sql, nil, nil, &errmsg) != SQLITE_OK {
            let msg = errmsg.map { String(cString: $0) } ?? "Unknown error"
            sqlite3_free(errmsg)
            throw NSError(domain: "SpatiotemporalSQLiteStore", code: 2, userInfo: [NSLocalizedDescriptionKey: msg])
        }
    }

    private static func bootstrapSchemaRaw(_ database: OpaquePointer) throws {
        let ddl = """
        CREATE TABLE IF NOT EXISTS spatiotemporal_coordinates (
            coord_id TEXT PRIMARY KEY NOT NULL,
            valence REAL NOT NULL,
            arousal REAL NOT NULL,
            absolute_time_sec REAL NOT NULL,
            homeostatic_delta REAL NOT NULL DEFAULT 0.0,
            created_at REAL NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_st_coords_time ON spatiotemporal_coordinates(absolute_time_sec);

        CREATE TABLE IF NOT EXISTS semantic_entities (
            entity_id TEXT PRIMARY KEY NOT NULL,
            entity_type TEXT NOT NULL,
            raw_text TEXT NOT NULL,
            lexical_hash TEXT NOT NULL UNIQUE,
            created_at REAL NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_semantic_hash ON semantic_entities(lexical_hash);

        CREATE TABLE IF NOT EXISTS homeostatic_binding_links (
            link_id TEXT PRIMARY KEY NOT NULL,
            coord_id TEXT NOT NULL REFERENCES spatiotemporal_coordinates(coord_id) ON DELETE CASCADE,
            entity_id TEXT NOT NULL REFERENCES semantic_entities(entity_id) ON DELETE CASCADE,
            binding_weight REAL NOT NULL DEFAULT 0.5,
            initial_reward REAL NOT NULL DEFAULT 0.0,
            last_activated_time REAL NOT NULL,
            decay_lambda REAL NOT NULL DEFAULT 0.05,
            created_at REAL NOT NULL,
            UNIQUE(coord_id, entity_id)
        );
        CREATE INDEX IF NOT EXISTS idx_hbl_coord ON homeostatic_binding_links(coord_id);
        CREATE INDEX IF NOT EXISTS idx_hbl_entity ON homeostatic_binding_links(entity_id);
        """
        try executeRaw(database, sql: ddl)
    }

    public func insertCoordinate(_ coord: SpatiotemporalCoordinate) throws {
        let sql = "INSERT INTO spatiotemporal_coordinates (coord_id, valence, arousal, absolute_time_sec, homeostatic_delta, created_at) VALUES (?, ?, ?, ?, ?, ?);"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw NSError(domain: "SpatiotemporalSQLiteStore", code: 3, userInfo: [NSLocalizedDescriptionKey: "Prepare failed"])
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (coord.coordID as NSString).utf8String, -1, Self.transient)
        sqlite3_bind_double(stmt, 2, coord.valence)
        sqlite3_bind_double(stmt, 3, coord.arousal)
        sqlite3_bind_double(stmt, 4, coord.absoluteTimeSec)
        sqlite3_bind_double(stmt, 5, coord.homeostaticDelta)
        sqlite3_bind_double(stmt, 6, coord.createdAt)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw NSError(domain: "SpatiotemporalSQLiteStore", code: 4, userInfo: [NSLocalizedDescriptionKey: "Step failed"])
        }
    }

    public func insertEntity(_ entity: SemanticEntity) throws {
        let sql = "INSERT INTO semantic_entities (entity_id, entity_type, raw_text, lexical_hash, created_at) VALUES (?, ?, ?, ?, ?) ON CONFLICT(lexical_hash) DO NOTHING;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw NSError(domain: "SpatiotemporalSQLiteStore", code: 5, userInfo: [NSLocalizedDescriptionKey: "Prepare failed"])
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (entity.entityID as NSString).utf8String, -1, Self.transient)
        sqlite3_bind_text(stmt, 2, (entity.entityType.rawValue as NSString).utf8String, -1, Self.transient)
        sqlite3_bind_text(stmt, 3, (entity.rawText as NSString).utf8String, -1, Self.transient)
        sqlite3_bind_text(stmt, 4, (entity.lexicalHash as NSString).utf8String, -1, Self.transient)
        sqlite3_bind_double(stmt, 5, entity.createdAt)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw NSError(domain: "SpatiotemporalSQLiteStore", code: 6, userInfo: [NSLocalizedDescriptionKey: "Step failed"])
        }
    }

    public func insertBindingLink(
        linkID: String = UUID().uuidString,
        coordID: String,
        entityID: String,
        bindingWeight: Double = 0.5,
        initialReward: Double = 0.0,
        lastActivatedTime: Double = ProcessInfo.processInfo.systemUptime,
        decayLambda: Double = 0.05,
        createdAt: Double = Date().timeIntervalSince1970
    ) throws {
        let sql = """
        INSERT INTO homeostatic_binding_links (link_id, coord_id, entity_id, binding_weight, initial_reward, last_activated_time, decay_lambda, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(coord_id, entity_id) DO UPDATE SET
            binding_weight = excluded.binding_weight,
            last_activated_time = excluded.last_activated_time;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw NSError(domain: "SpatiotemporalSQLiteStore", code: 7, userInfo: [NSLocalizedDescriptionKey: "Prepare binding link failed"])
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (linkID as NSString).utf8String, -1, Self.transient)
        sqlite3_bind_text(stmt, 2, (coordID as NSString).utf8String, -1, Self.transient)
        sqlite3_bind_text(stmt, 3, (entityID as NSString).utf8String, -1, Self.transient)
        sqlite3_bind_double(stmt, 4, bindingWeight)
        sqlite3_bind_double(stmt, 5, initialReward)
        sqlite3_bind_double(stmt, 6, lastActivatedTime)
        sqlite3_bind_double(stmt, 7, decayLambda)
        sqlite3_bind_double(stmt, 8, createdAt)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw NSError(domain: "SpatiotemporalSQLiteStore", code: 8, userInfo: [NSLocalizedDescriptionKey: "Step binding link failed"])
        }
    }

    public func withDatabase<T: Sendable>(_ block: @Sendable (OpaquePointer) throws -> T) throws -> T {
        try block(db)
    }

    public func queryBindingLinksCount() throws -> Int {
        let sql = "SELECT COUNT(*) FROM homeostatic_binding_links;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return 0 }
        defer { sqlite3_finalize(stmt) }
        if sqlite3_step(stmt) == SQLITE_ROW {
            return Int(sqlite3_column_int(stmt, 0))
        }
        return 0
    }

    public func queryCoordinatesCount() throws -> Int {
        let sql = "SELECT COUNT(*) FROM spatiotemporal_coordinates;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return 0 }
        defer { sqlite3_finalize(stmt) }
        if sqlite3_step(stmt) == SQLITE_ROW {
            return Int(sqlite3_column_int(stmt, 0))
        }
        return 0
    }

    public func queryEntitiesCount() throws -> Int {
        let sql = "SELECT COUNT(*) FROM semantic_entities;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return 0 }
        defer { sqlite3_finalize(stmt) }
        if sqlite3_step(stmt) == SQLITE_ROW {
            return Int(sqlite3_column_int(stmt, 0))
        }
        return 0
    }

    public func queryTotalBindingEnergy() throws -> Double {
        let sql = "SELECT COALESCE(SUM(binding_weight), 0.0) FROM homeostatic_binding_links;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return 0.0 }
        defer { sqlite3_finalize(stmt) }
        if sqlite3_step(stmt) == SQLITE_ROW {
            return sqlite3_column_double(stmt, 0)
        }
        return 0.0
    }
}
