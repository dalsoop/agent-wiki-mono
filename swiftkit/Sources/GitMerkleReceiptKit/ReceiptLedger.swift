import Foundation
import FastDiskIOKit

/// SQLite WAL 기반 영수증 원장 저장소
public struct ReceiptLedger: Sendable {
    private let engine: FastSQLiteEngine

    public init(databasePath: String) throws {
        let parentDir = URL(fileURLWithPath: databasePath).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        self.engine = try FastSQLiteEngine.open(path: databasePath, readOnly: false)
        try createTableIfNeeded()
    }

    private func createTableIfNeeded() throws {
        let sql = """
        CREATE TABLE IF NOT EXISTS lint_receipts (
            target_path      TEXT NOT NULL,
            tree_oid         TEXT NOT NULL,
            ruleset_digest   TEXT NOT NULL,
            toolchain_hash   TEXT NOT NULL,
            verdict          TEXT NOT NULL,
            violation_count  INTEGER NOT NULL,
            findings_blob    BLOB,
            duration_ms      REAL NOT NULL,
            issued_at        INTEGER NOT NULL,
            PRIMARY KEY (target_path, tree_oid, ruleset_digest, toolchain_hash)
        ) WITHOUT ROWID;

        CREATE INDEX IF NOT EXISTS idx_receipts_lookup 
        ON lint_receipts (target_path, tree_oid);
        """
        try engine.exec(sql: sql)
    }

    public func queryReceipt(
        targetPath: String,
        treeOID: String,
        rulesetDigest: String,
        toolchainHash: String
    ) throws -> AnalysisReceipt? {
        let sql = """
        SELECT verdict, violation_count, findings_blob, duration_ms, issued_at
        FROM lint_receipts
        WHERE target_path = ?
          AND tree_oid = ?
          AND ruleset_digest = ?
          AND toolchain_hash = ?
        LIMIT 1;
        """
        let rows = try engine.query(sql: sql, binds: [targetPath, treeOID, rulesetDigest, toolchainHash])
        guard let row = rows.first else { return nil }

        guard let verdictRaw = row["verdict"]?.stringValue,
              let verdict = AnalysisReceipt.Verdict(rawValue: verdictRaw),
              let violationCount = row["violation_count"]?.intValue,
              let durationMs = row["duration_ms"]?.doubleValue,
              let issuedEpoch = row["issued_at"]?.int64Value else {
            return nil
        }

        return AnalysisReceipt(
            targetPath: targetPath,
            treeOID: treeOID,
            rulesetDigest: rulesetDigest,
            toolchainHash: toolchainHash,
            verdict: verdict,
            violationCount: violationCount,
            findingsData: row["findings_blob"]?.dataValue,
            durationMs: durationMs,
            issuedAt: Date(timeIntervalSince1970: Double(issuedEpoch) / 1000.0)
        )
    }

    public func issueReceipt(_ receipt: AnalysisReceipt) throws {
        let sql = """
        INSERT OR REPLACE INTO lint_receipts (
            target_path, tree_oid, ruleset_digest, toolchain_hash,
            verdict, violation_count, findings_blob, duration_ms, issued_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        let issuedEpoch = Int64(receipt.issuedAt.timeIntervalSince1970 * 1000.0)
        try engine.run(sql: sql, binds: [
            receipt.targetPath,
            receipt.treeOID,
            receipt.rulesetDigest,
            receipt.toolchainHash,
            receipt.verdict.rawValue,
            receipt.violationCount,
            receipt.findingsData,
            receipt.durationMs,
            issuedEpoch
        ])
    }

    public func verifyReceipt(
        targetPath: String,
        treeOID: String,
        rulesetDigest: String,
        toolchainHash: String
    ) throws -> ReceiptVerificationResult {
        guard let receipt = try queryReceipt(
            targetPath: targetPath,
            treeOID: treeOID,
            rulesetDigest: rulesetDigest,
            toolchainHash: toolchainHash
        ) else {
            return .missing
        }
        if receipt.verdict == .fail {
            return .stale(reason: "Cached receipt verdict is FAIL (\(receipt.violationCount) violations)")
        }
        return .valid(receipt)
    }
}
