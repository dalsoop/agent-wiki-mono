import Foundation
import FastDiskIOKit

/// SQLite WAL 기반의 영수증 원장 데이터베이스.
/// `~/.ssot/receipts/agent-lint-receipts.db`에 앱 및 루트 트리 영수증을 원자적으로 기록/조회한다.
/// PRAGMA synchronous = NORMAL, PRAGMA journal_mode = WAL을 준수한다.
public struct ReceiptLedgerDatabase: Sendable {
    public static let defaultDatabasePath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.ssot/receipts/agent-lint-receipts.db"
    }()

    public let path: String
    private let engine: FastSQLiteEngine

    public init(databasePath: String = ReceiptLedgerDatabase.defaultDatabasePath) throws {
        self.path = databasePath

        // 상위 디렉터리 보장
        let dir = (databasePath as NSString).deletingLastPathComponent
        if !FileManager.default.fileExists(atPath: dir) {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }

        self.engine = try FastSQLiteEngine.open(path: databasePath, readOnly: false)
        try createTablesIfNeeded()
    }

    private func createTablesIfNeeded() throws {
        let createTablesSQL = """
        CREATE TABLE IF NOT EXISTS app_tree_receipts (
            scope TEXT NOT NULL,
            subtree_oid TEXT NOT NULL,
            ruleset_digest TEXT NOT NULL,
            verdict TEXT NOT NULL,
            violations_count INTEGER NOT NULL,
            by_rule_json TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            PRIMARY KEY (scope, subtree_oid, ruleset_digest)
        );
        CREATE INDEX IF NOT EXISTS idx_app_tree_oid ON app_tree_receipts (subtree_oid, ruleset_digest);

        CREATE TABLE IF NOT EXISTS repo_root_receipts (
            root_tree_oid TEXT NOT NULL,
            ruleset_digest TEXT NOT NULL,
            total_violations INTEGER NOT NULL,
            by_rule_json TEXT NOT NULL,
            by_app_json TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            PRIMARY KEY (root_tree_oid, ruleset_digest)
        );
        """
        try engine.exec(sql: createTablesSQL)
    }

    // MARK: - App Tree Receipts

    /// 개별 앱 영수증 원자적 기록 (UPSERT)
    public func recordAppReceipt(_ receipt: AppTreeReceipt) throws {
        let sql = """
        INSERT OR REPLACE INTO app_tree_receipts
        (scope, subtree_oid, ruleset_digest, verdict, violations_count, by_rule_json, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?);
        """
        try engine.run(sql: sql, binds: [
            receipt.scope,
            receipt.subtreeOID,
            receipt.rulesetDigest,
            receipt.verdict,
            receipt.violationsCount,
            receipt.byRuleJSON,
            receipt.updatedAt
        ])
    }

    /// scope, subtree_oid, ruleset_digest로 앱 영수증 조회
    public func getAppReceipt(scope: String, subtreeOID: String, rulesetDigest: String) throws -> AppTreeReceipt? {
        let sql = """
        SELECT scope, subtree_oid, ruleset_digest, verdict, violations_count, by_rule_json, updated_at
        FROM app_tree_receipts
        WHERE scope = ? AND subtree_oid = ? AND ruleset_digest = ?
        LIMIT 1;
        """
        let rows = try engine.query(sql: sql, binds: [scope, subtreeOID, rulesetDigest])
        guard let row = rows.first else { return nil }
        return rowToAppReceipt(row)
    }

    /// subtree_oid와 ruleset_digest로 앱 영수증 조회 (인덱스 활용 O(1))
    public func getAppReceipt(subtreeOID: String, rulesetDigest: String) throws -> AppTreeReceipt? {
        let sql = """
        SELECT scope, subtree_oid, ruleset_digest, verdict, violations_count, by_rule_json, updated_at
        FROM app_tree_receipts
        WHERE subtree_oid = ? AND ruleset_digest = ?
        LIMIT 1;
        """
        let rows = try engine.query(sql: sql, binds: [subtreeOID, rulesetDigest])
        guard let row = rows.first else { return nil }
        return rowToAppReceipt(row)
    }

    /// 특정 ruleset_digest의 모든 앱 영수증 조회
    public func getAllAppReceipts(rulesetDigest: String? = nil) throws -> [AppTreeReceipt] {
        let sql: String
        let binds: [Any?]
        if let rulesetDigest {
            sql = """
            SELECT scope, subtree_oid, ruleset_digest, verdict, violations_count, by_rule_json, updated_at
            FROM app_tree_receipts
            WHERE ruleset_digest = ?;
            """
            binds = [rulesetDigest]
        } else {
            sql = """
            SELECT scope, subtree_oid, ruleset_digest, verdict, violations_count, by_rule_json, updated_at
            FROM app_tree_receipts;
            """
            binds = []
        }
        let rows = try engine.query(sql: sql, binds: binds)
        return rows.compactMap(rowToAppReceipt)
    }

    // MARK: - Repo Root Receipts

    /// 레포 루트 스냅샷 영수증 원자적 기록 (UPSERT)
    public func recordRepoRootReceipt(_ receipt: RepoRootReceipt) throws {
        let sql = """
        INSERT OR REPLACE INTO repo_root_receipts
        (root_tree_oid, ruleset_digest, total_violations, by_rule_json, by_app_json, updated_at)
        VALUES (?, ?, ?, ?, ?, ?);
        """
        try engine.run(sql: sql, binds: [
            receipt.rootTreeOID,
            receipt.rulesetDigest,
            receipt.totalViolations,
            receipt.byRuleJSON,
            receipt.byAppJSON,
            receipt.updatedAt
        ])
    }

    /// root_tree_oid와 ruleset_digest로 루트 영수증 조회 (Primary Key O(1))
    public func getRepoRootReceipt(rootTreeOID: String, rulesetDigest: String) throws -> RepoRootReceipt? {
        let sql = """
        SELECT root_tree_oid, ruleset_digest, total_violations, by_rule_json, by_app_json, updated_at
        FROM repo_root_receipts
        WHERE root_tree_oid = ? AND ruleset_digest = ?
        LIMIT 1;
        """
        let rows = try engine.query(sql: sql, binds: [rootTreeOID, rulesetDigest])
        guard let row = rows.first else { return nil }
        return rowToRepoRootReceipt(row)
    }

    // MARK: - Cleanup / Diagnostics

    /// 데이터베이스 내 모든 영수증 레코드 삭제 (테스트 또는 초기화용)
    public func clear() throws {
        try engine.exec(sql: "DELETE FROM app_tree_receipts; DELETE FROM repo_root_receipts;")
    }

    private func rowToAppReceipt(_ row: FastSQLiteRow) -> AppTreeReceipt? {
        guard
            let scope = row.string(for: "scope"),
            let subtreeOID = row.string(for: "subtree_oid"),
            let rulesetDigest = row.string(for: "ruleset_digest"),
            let verdict = row.string(for: "verdict"),
            let violationsCount = row.int(for: "violations_count"),
            let byRuleJSON = row.string(for: "by_rule_json"),
            let updatedAt = row.string(for: "updated_at")
        else {
            return nil
        }
        return AppTreeReceipt(
            scope: scope,
            subtreeOID: subtreeOID,
            rulesetDigest: rulesetDigest,
            verdict: verdict,
            violationsCount: violationsCount,
            byRuleJSON: byRuleJSON,
            updatedAt: updatedAt
        )
    }

    private func rowToRepoRootReceipt(_ row: FastSQLiteRow) -> RepoRootReceipt? {
        guard
            let rootTreeOID = row.string(for: "root_tree_oid"),
            let rulesetDigest = row.string(for: "ruleset_digest"),
            let totalViolations = row.int(for: "total_violations"),
            let byRuleJSON = row.string(for: "by_rule_json"),
            let byAppJSON = row.string(for: "by_app_json"),
            let updatedAt = row.string(for: "updated_at")
        else {
            return nil
        }
        return RepoRootReceipt(
            rootTreeOID: rootTreeOID,
            rulesetDigest: rulesetDigest,
            totalViolations: totalViolations,
            byRuleJSON: byRuleJSON,
            byAppJSON: byAppJSON,
            updatedAt: updatedAt
        )
    }
}
