import Foundation
import MoneyLedgerModels
import SQLite3

public enum LedgerStoreError: Error, Equatable, CustomStringConvertible {
    case open(String)
    case sqlite(String)
    case encode(String)
    case decode(String)
    case notFound(String)
    case ambiguousID(String)
    case referencedByTransactions(id: String, count: Int)

    public var description: String {
        switch self {
        case let .open(message): "원장 DB 열기 실패: \(message)"
        case let .sqlite(message): "원장 DB 오류: \(message)"
        case let .encode(message): "원장 인코드 실패: \(message)"
        case let .decode(message): "원장 디코드 실패: \(message)"
        case let .notFound(idPrefix): "해당 id 없음: \(idPrefix)"
        case let .ambiguousID(idPrefix): "id 접두사가 모호합니다(더 길게): \(idPrefix)"
        case let .referencedByTransactions(id, count):
            "\(id) 를 참조하는 거래가 \(count)건 있어 삭제할 수 없습니다 — 거래를 먼저 정리하세요"
        }
    }
}

/// 거래 조회 필터.
public struct TransactionQuery: Sendable {
    public var fromDate: String?
    public var toDate: String?
    public var accountID: String?
    public var cardID: String?
    public var category: String?
    /// 귀속 사업체 필터(BusinessProfile.id 정확 일치). nil 이면 사업체 무관 전체.
    public var businessID: String?
    public var limit: Int?

    public init(
        fromDate: String? = nil,
        toDate: String? = nil,
        accountID: String? = nil,
        cardID: String? = nil,
        category: String? = nil,
        businessID: String? = nil,
        limit: Int? = nil
    ) {
        self.fromDate = fromDate
        self.toDate = toDate
        self.accountID = accountID
        self.cardID = cardID
        self.category = category
        self.businessID = businessID
        self.limit = limit
    }
}

/// 거래 삽입 결과 — 중복이면 기존 행을 알려주고 성공으로 처리한다(에이전트 재시도 멱등성).
public struct TransactionInsertOutcome: Sendable, Equatable {
    public let transaction: MoneyTransaction
    public let duplicate: Bool
}

/// Ledger 원장 저장소 — CalendarSQLiteStore 구조 이식(actor + WAL + payload BLOB JSON).
/// 질의 키만 컬럼으로 승격하고 전체 모델은 payload 에 산다(필드 추가 = 옵셔널, 스키마 변경 없음).
public actor LedgerStore {
    /// sqlite 핸들 소유자 — actor 격리 저장소라 Sendable 일 필요가 없다. deinit 이 닫는다.
    private final class Connection {
        let handle: OpaquePointer
        init(handle: OpaquePointer) { self.handle = handle }
        deinit { sqlite3_close_v2(handle) }
    }

    private let connection: Connection
    private var database: OpaquePointer { connection.handle }
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var opened: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path, &opened, flags, nil) == SQLITE_OK, let opened else {
            let message = opened.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            if let opened { sqlite3_close(opened) }
            throw LedgerStoreError.open(message)
        }
        connection = Connection(handle: opened)
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        try Self.execute(opened, sql: "PRAGMA journal_mode=WAL")
        try Self.execute(opened, sql: "PRAGMA foreign_keys=ON")
        try Self.execute(opened, sql: "PRAGMA busy_timeout=5000")
        try Self.execute(opened, sql: Self.schema)
        // CREATE TABLE IF NOT EXISTS 는 기존 테이블을 못 바꾼다 — 승격 컬럼은 migrate 가 덧붙인다.
        try Self.migrate(opened)
    }

    public init(context: LedgerContext) throws {
        try self.init(url: context.databaseURL)
    }

    // MARK: - 공통 내부 (같은 모듈의 extension LedgerStore 가 호출)

    func encode<T: Encodable>(_ value: T) throws -> Data {
        do { return try encoder.encode(value) }
        catch { throw LedgerStoreError.encode(String(describing: error)) }
    }

    func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do { return try decoder.decode(type, from: data) }
        catch { throw LedgerStoreError.decode(String(describing: error)) }
    }

    func executeMutation(_ sql: String, bindings: (OpaquePointer) -> Void) throws {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        bindings(statement)
        try stepDone(statement)
    }

    func inTransaction<T>(_ body: () throws -> T) throws -> T {
        try Self.execute(database, sql: "BEGIN IMMEDIATE")
        do {
            let value = try body()
            try Self.execute(database, sql: "COMMIT")
            return value
        } catch {
            try? Self.execute(database, sql: "ROLLBACK")
            throw error
        }
    }

    func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw sqliteError()
        }
        return statement
    }

    func bind(_ value: String, at index: Int32, to statement: OpaquePointer) {
        sqlite3_bind_text(statement, index, value, -1, Self.transient)
    }

    func bindOptional(_ value: String?, at index: Int32, to statement: OpaquePointer) {
        if let value { bind(value, at: index, to: statement) } else { sqlite3_bind_null(statement, index) }
    }

    func bind(_ value: Data, at index: Int32, to statement: OpaquePointer) {
        _ = value.withUnsafeBytes { bytes in
            sqlite3_bind_blob(statement, index, bytes.baseAddress, Int32(bytes.count), Self.transient)
        }
    }

    func data(at index: Int32, in statement: OpaquePointer) -> Data {
        let count = Int(sqlite3_column_bytes(statement, index))
        guard count > 0, let bytes = sqlite3_column_blob(statement, index) else { return Data() }
        return Data(bytes: bytes, count: count)
    }

    func stepDone(_ statement: OpaquePointer) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else { throw sqliteError() }
    }

    func verifyRead(_ statement: OpaquePointer) throws {
        let status = sqlite3_errcode(database)
        guard status == SQLITE_OK || status == SQLITE_DONE || status == SQLITE_ROW else {
            throw sqliteError()
        }
    }

    func sqliteError() -> LedgerStoreError {
        .sqlite(String(cString: sqlite3_errmsg(database)))
    }

    static func execute(_ database: OpaquePointer, sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(database, sql, nil, nil, &errorMessage) == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(database))
            sqlite3_free(errorMessage)
            throw LedgerStoreError.sqlite(message)
        }
    }

    func optionalOne<T: Decodable>(_ type: T.Type, table: String, idPrefix: String) throws -> T? {
        precondition(Self.idPrefixTables.contains(table))
        let statement = try prepare("SELECT payload FROM \(table) WHERE id LIKE ? ORDER BY id LIMIT 2")
        defer { sqlite3_finalize(statement) }
        bind(escapeLike(idPrefix) + "%", at: 1, to: statement)
        let values = try collect(type, statement: statement)
        if values.count > 1 { throw LedgerStoreError.ambiguousID(idPrefix) }
        return values.first
    }

    func requireOne<T: Decodable>(_ type: T.Type, table: String, idPrefix: String) throws -> T {
        guard let value = try optionalOne(type, table: table, idPrefix: idPrefix) else {
            throw LedgerStoreError.notFound(idPrefix)
        }
        return value
    }

    func escapeLike(_ raw: String) -> String {
        // UUID id 라 실질 위험은 없지만 LIKE 와일드카드는 리터럴로 다룬다.
        raw.replacingOccurrences(of: "%", with: "").replacingOccurrences(of: "_", with: "")
    }

    func listPayloads<T: Decodable>(_ type: T.Type, sql: String) throws -> [T] {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        return try collect(type, statement: statement)
    }

    func collect<T: Decodable>(_ type: T.Type, statement: OpaquePointer) throws -> [T] {
        var values: [T] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            values.append(try decode(type, from: data(at: 0, in: statement)))
        }
        try verifyRead(statement)
        return values
    }

    func scalarCount(_ sql: String) throws -> Int {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int(statement, 0))
    }

    func transactionCount(instrumentColumn: String, id: String) throws -> Int {
        // instrumentColumn 은 내부 상수 호출뿐이라 SQL 조립이 안전하다.
        let statement = try prepare("SELECT COUNT(*) FROM transactions WHERE \(instrumentColumn) = ?")
        defer { sqlite3_finalize(statement) }
        bind(id, at: 1, to: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int(statement, 0))
    }

    private static let idPrefixTables: Set<String> = [
        "accounts", "cards", "subscriptions", "transactions", "import_batches",
        "businesses", "attachments", "budgets", "recurring_templates",
    ]

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    // time_sort: payload 의 time 을 생성 컬럼으로 승격 — 날짜 내 정렬용(없으면 빈 문자열).
    private static let schema = """
        CREATE TABLE IF NOT EXISTS metadata (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS accounts (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          bank TEXT NOT NULL,
          last4 TEXT NOT NULL DEFAULT '',
          currency TEXT NOT NULL DEFAULT 'KRW',
          archived INTEGER NOT NULL DEFAULT 0,
          payload BLOB NOT NULL
        );
        CREATE TABLE IF NOT EXISTS cards (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          issuer TEXT NOT NULL,
          last4 TEXT NOT NULL DEFAULT '',
          linked_account_id TEXT,
          archived INTEGER NOT NULL DEFAULT 0,
          payload BLOB NOT NULL
        );
        CREATE TABLE IF NOT EXISTS subscriptions (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          amount_minor INTEGER NOT NULL,
          currency TEXT NOT NULL DEFAULT 'KRW',
          period TEXT NOT NULL,
          status TEXT NOT NULL DEFAULT 'active',
          next_billing_at TEXT,
          archived INTEGER NOT NULL DEFAULT 0,
          payload BLOB NOT NULL
        );
        CREATE TABLE IF NOT EXISTS transactions (
          id TEXT PRIMARY KEY,
          date TEXT NOT NULL,
          amount_minor INTEGER NOT NULL,
          currency TEXT NOT NULL DEFAULT 'KRW',
          account_id TEXT,
          card_id TEXT,
          description TEXT NOT NULL DEFAULT '',
          category TEXT,
          content_hash TEXT NOT NULL,
          import_batch_id TEXT,
          business_id TEXT,
          payload BLOB NOT NULL,
          time_sort TEXT NOT NULL GENERATED ALWAYS AS (COALESCE(json_extract(payload, '$.time'), '')) STORED
        );
        CREATE UNIQUE INDEX IF NOT EXISTS idx_tx_hash ON transactions(content_hash);
        CREATE INDEX IF NOT EXISTS idx_tx_date ON transactions(date);
        CREATE INDEX IF NOT EXISTS idx_tx_account ON transactions(account_id);
        CREATE INDEX IF NOT EXISTS idx_tx_batch ON transactions(import_batch_id);
        CREATE TABLE IF NOT EXISTS import_batches (
          id TEXT PRIMARY KEY,
          created_at REAL NOT NULL,
          source_file TEXT NOT NULL,
          inserted INTEGER NOT NULL,
          payload BLOB NOT NULL
        );
        CREATE TABLE IF NOT EXISTS businesses (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          registration_number TEXT NOT NULL DEFAULT '',
          archived INTEGER NOT NULL DEFAULT 0,
          payload BLOB NOT NULL
        );
        CREATE TABLE IF NOT EXISTS attachments (
          id TEXT PRIMARY KEY,
          owner_kind TEXT NOT NULL,
          owner_id TEXT NOT NULL,
          file_name TEXT NOT NULL,
          original_name TEXT NOT NULL DEFAULT '',
          payload BLOB NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_attach_owner ON attachments(owner_kind, owner_id);
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
        CREATE INDEX IF NOT EXISTS idx_budgets_month ON budgets(month);
        CREATE INDEX IF NOT EXISTS idx_budgets_category ON budgets(category);
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
          created_at REAL NOT NULL DEFAULT 0,
          updated_at REAL NOT NULL DEFAULT 0,
          payload BLOB NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_recurring_active ON recurring_templates(is_active);
        """
}
