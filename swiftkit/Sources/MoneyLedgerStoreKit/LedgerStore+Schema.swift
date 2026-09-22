import Foundation
import SQLite3

extension LedgerStore {
    /// 스키마 버전 — 질의 키 컬럼을 승격할 때만 올린다. payload 필드만 늘어나면 그대로다.
    ///   1  최초(계좌·카드·구독·거래·배치·사업자·첨부)
    ///   2  transactions.business_id 승격(거래 사업체 귀속, 2026-09)
    ///   4  budgets(month, timestamps) 승격 및 recurring_templates 추가
    public static let schemaVersion = "4"

    /// 열린 원장에 기록된 스키마 버전(metadata.schema_version). 마이그레이션 검증용.
    public func storedSchemaVersion() throws -> String? {
        let statement = try prepare("SELECT value FROM metadata WHERE key = 'schema_version'")
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW, let text = sqlite3_column_text(statement, 0) else {
            return nil
        }
        return String(cString: text)
    }

    /// 질의 키 승격 이력 — 멱등. 옛 원장은 `CREATE TABLE IF NOT EXISTS` 로 컬럼이 안 생기므로
    /// `PRAGMA table_info` 로 있는지 보고 `ALTER TABLE … ADD COLUMN` 한다. 인덱스는 컬럼이
    /// 보장된 뒤에 만들어야 하므로 schema 문자열이 아니라 여기서 만든다.
    static func migrate(_ database: OpaquePointer) throws {
        try addColumnIfMissing(database, table: "transactions", column: "business_id", definition: "TEXT")
        try execute(database, sql: "CREATE INDEX IF NOT EXISTS idx_tx_business ON transactions(business_id)")
        try execute(database, sql: """
            CREATE TABLE IF NOT EXISTS budgets (
              id TEXT PRIMARY KEY,
              category TEXT NOT NULL,
              month TEXT,
              amount_minor INTEGER NOT NULL,
              currency TEXT NOT NULL DEFAULT 'KRW',
              created_at REAL NOT NULL DEFAULT 0,
              updated_at REAL NOT NULL DEFAULT 0,
              payload BLOB NOT NULL
            );
            """)
        try addColumnIfMissing(database, table: "budgets", column: "month", definition: "TEXT")
        try addColumnIfMissing(database, table: "budgets", column: "created_at", definition: "REAL NOT NULL DEFAULT 0")
        try addColumnIfMissing(database, table: "budgets", column: "updated_at", definition: "REAL NOT NULL DEFAULT 0")
        try execute(database, sql: "CREATE INDEX IF NOT EXISTS idx_budgets_month ON budgets(month)")
        try execute(database, sql: "CREATE INDEX IF NOT EXISTS idx_budgets_category ON budgets(category)")

        try execute(database, sql: """
            CREATE TABLE IF NOT EXISTS recurring_templates (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              day_of_month INTEGER NOT NULL,
              amount_minor INTEGER NOT NULL,
              currency TEXT NOT NULL DEFAULT 'KRW',
              kind TEXT NOT NULL DEFAULT 'expense',
              category TEXT,
              account_id TEXT,
              transfer_target_account_id TEXT,
              memo TEXT,
              is_active INTEGER NOT NULL DEFAULT 1,
              created_at REAL NOT NULL,
              updated_at REAL NOT NULL,
              payload BLOB NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_recurring_active ON recurring_templates(is_active);
            """)

        try execute(database, sql: """
            CREATE TABLE IF NOT EXISTS tombstones (
              entity_type TEXT NOT NULL,
              entity_id TEXT NOT NULL,
              deleted_at REAL NOT NULL,
              PRIMARY KEY(entity_type, entity_id)
            );
            CREATE INDEX IF NOT EXISTS idx_tombstones_type ON tombstones(entity_type);
            """)
        try execute(database, sql: """
            INSERT INTO metadata(key, value) VALUES('schema_version', '\(schemaVersion)')
            ON CONFLICT(key) DO UPDATE SET value=excluded.value
            """)
    }

    /// table·column·definition 은 내부 상수 호출뿐이라 SQL 조립이 안전하다.
    static func addColumnIfMissing(
        _ database: OpaquePointer, table: String, column: String, definition: String
    ) throws {
        let existing = try columnNames(database, table: table)
        guard !existing.contains(column) else { return }
        try execute(database, sql: "ALTER TABLE \(table) ADD COLUMN \(column) \(definition)")
    }

    static func columnNames(_ database: OpaquePointer, table: String) throws -> [String] {
        var statement: OpaquePointer?
        let prepared = sqlite3_prepare_v2(database, "PRAGMA table_info(\(table))", -1, &statement, nil)
        guard prepared == SQLITE_OK, let statement else {
            throw LedgerStoreError.sqlite(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }
        var names: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let text = sqlite3_column_text(statement, 1) else { continue }
            names.append(String(cString: text))
        }
        return names
    }
}
