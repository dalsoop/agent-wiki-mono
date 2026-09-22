import Foundation
import SQLite3

/// schema_version 1 원장 — transactions 에 business_id 컬럼이 없고 payload 에도 키가 없다.
/// 마이그레이션 테스트 전용: LedgerStore 가 열면 컬럼이 덧붙고 기존 행은 businessID nil 로 읽혀야 한다.
enum LegacyLedgerFixture {
    enum FixtureError: Error {
        case open
        case exec(String)
    }

    static func write(to url: URL, transactionID: String) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        var opened: OpaquePointer?
        guard sqlite3_open(url.path, &opened) == SQLITE_OK, let handle = opened else {
            throw FixtureError.open
        }
        defer { sqlite3_close(handle) }
        let payload = """
        {"id":"\(transactionID)","date":"2026-01-15","amountMinor":-1000,"currency":"KRW",\
        "accountID":"acct-1","description":"옛 거래","contentHash":"legacy-hash-1",\
        "createdAt":"2026-01-15T00:00:00Z"}
        """
        let sql = """
        CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL);
        INSERT INTO metadata(key, value) VALUES('schema_version', '1');
        CREATE TABLE transactions (
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
          payload BLOB NOT NULL,
          time_sort TEXT NOT NULL GENERATED ALWAYS AS (COALESCE(json_extract(payload, '$.time'), '')) STORED
        );
        CREATE UNIQUE INDEX idx_tx_hash ON transactions(content_hash);
        INSERT INTO transactions(id, date, amount_minor, currency, account_id, description, content_hash, payload)
        VALUES('\(transactionID)', '2026-01-15', -1000, 'KRW', 'acct-1', '옛 거래', 'legacy-hash-1', '\(payload)');
        """
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else {
            throw FixtureError.exec(String(cString: sqlite3_errmsg(handle)))
        }
    }
}
