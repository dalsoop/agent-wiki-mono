import Foundation
import MoneyLedgerModels
import SQLite3

extension LedgerStore {
    // MARK: - 툼스톤 (Tombstones - 삭제 추적 및 좀비 원장 부활 방지)

    public func recordTombstone(
        entityType: String,
        entityID: String,
        deletedAt: Date = Date()
    ) throws {
        try executeMutation("""
            INSERT INTO tombstones(entity_type, entity_id, deleted_at)
            VALUES(?, ?, ?)
            ON CONFLICT(entity_type, entity_id) DO UPDATE SET
              deleted_at=excluded.deleted_at
            """) { statement in
            bind(entityType, at: 1, to: statement)
            bind(entityID, at: 2, to: statement)
            sqlite3_bind_double(statement, 3, deletedAt.timeIntervalSince1970)
        }
    }

    public func removeTombstone(entityType: String, entityID: String) throws {
        try executeMutation("DELETE FROM tombstones WHERE entity_type = ? AND entity_id = ?") { statement in
            bind(entityType, at: 1, to: statement)
            bind(entityID, at: 2, to: statement)
        }
    }

    public func tombstones(entityType: String? = nil) throws -> [TombstoneRecord] {
        let sql = entityType != nil
            ? "SELECT entity_type, entity_id, deleted_at FROM tombstones WHERE entity_type = ? ORDER BY deleted_at ASC"
            : "SELECT entity_type, entity_id, deleted_at FROM tombstones ORDER BY deleted_at ASC"
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        if let entityType {
            bind(entityType, at: 1, to: statement)
        }

        var results: [TombstoneRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let typeText = sqlite3_column_text(statement, 0),
                  let idText = sqlite3_column_text(statement, 1) else { continue }
            let type = String(cString: typeText)
            let id = String(cString: idText)
            let timestamp = sqlite3_column_double(statement, 2)
            results.append(TombstoneRecord(
                entityType: type,
                entityID: id,
                deletedAt: Date(timeIntervalSince1970: timestamp)
            ))
        }
        try verifyRead(statement)
        return results
    }

    public func tombstoneIDs(entityType: String) throws -> Set<String> {
        let statement = try prepare("SELECT entity_id FROM tombstones WHERE entity_type = ?")
        defer { sqlite3_finalize(statement) }
        bind(entityType, at: 1, to: statement)
        var ids = Set<String>()
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let text = sqlite3_column_text(statement, 0) else { continue }
            ids.insert(String(cString: text))
        }
        try verifyRead(statement)
        return ids
    }

    public func isTombstoned(entityType: String, entityID: String) throws -> Bool {
        let statement = try prepare("SELECT 1 FROM tombstones WHERE entity_type = ? AND entity_id = ? LIMIT 1")
        defer { sqlite3_finalize(statement) }
        bind(entityType, at: 1, to: statement)
        bind(entityID, at: 2, to: statement)
        return sqlite3_step(statement) == SQLITE_ROW
    }

    public func clearTombstones() throws {
        try executeMutation("DELETE FROM tombstones") { _ in }
    }
}
