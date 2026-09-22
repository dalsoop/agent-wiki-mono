import Foundation

/// Git Tree OID 및 Ruleset Digest 기반 O(1) 영수증 검증기.
/// SQLite WAL 원장을 조회하여 영수증이 존재하고 유효할 경우 0.005초(5ms) 이내에 `.valid(Receipt)`를 반환한다.
public struct ReceiptVerifier: Sendable {
    public let database: ReceiptLedgerDatabase

    public init(database: ReceiptLedgerDatabase) {
        self.database = database
    }

    public init(databasePath: String = ReceiptLedgerDatabase.defaultDatabasePath) throws {
        self.database = try ReceiptLedgerDatabase(databasePath: databasePath)
    }

    /// Tree OID (Root Tree OID 또는 Subtree OID)와 rulesetDigest를 기반으로 영수증 유효성을 검증한다.
    /// 영수증이 존재하고 유효하면 O(1) 시간(0.005초 이하)에 `.valid(Receipt)`를 반환한다.
    public func verify(treeOID: String, rulesetDigest: String) throws -> VerificationResult {
        let rootResult = try verifyRoot(rootTreeOID: treeOID, rulesetDigest: rulesetDigest)
        guard case .notFound = rootResult else {
            return rootResult
        }
        return try verifySubtreeOnly(treeOID: treeOID, rulesetDigest: rulesetDigest)
    }

    private func verifySubtreeOnly(treeOID: String, rulesetDigest: String) throws -> VerificationResult {
        guard let appReceipt = try database.getAppReceipt(subtreeOID: treeOID, rulesetDigest: rulesetDigest) else {
            return .notFound
        }
        return evaluateAppReceipt(appReceipt, treeOID: treeOID)
    }

    private func evaluateAppReceipt(_ appReceipt: AppTreeReceipt, treeOID: String) -> VerificationResult {
        guard appReceipt.verdict == "PASS" && appReceipt.violationsCount == 0 else {
            return .invalid(
                reason: "App scope '\(appReceipt.scope)' (subtree '\(treeOID)') verdict is '\(appReceipt.verdict)' with \(appReceipt.violationsCount) violation(s)",
                violationsCount: appReceipt.violationsCount
            )
        }
        return .valid(Receipt(appTree: appReceipt))
    }

    /// 루트 트리 OID 전용 검증
    public func verifyRoot(rootTreeOID: String, rulesetDigest: String) throws -> VerificationResult {
        guard let rootReceipt = try database.getRepoRootReceipt(rootTreeOID: rootTreeOID, rulesetDigest: rulesetDigest) else {
            return .notFound
        }
        return evaluateRootReceipt(rootReceipt, rootTreeOID: rootTreeOID)
    }

    private func evaluateRootReceipt(_ rootReceipt: RepoRootReceipt, rootTreeOID: String) -> VerificationResult {
        guard rootReceipt.totalViolations == 0 else {
            return .invalid(
                reason: "Repo root tree '\(rootTreeOID)' has \(rootReceipt.totalViolations) violation(s)",
                violationsCount: rootReceipt.totalViolations
            )
        }
        return .valid(Receipt(repoRoot: rootReceipt))
    }

    /// 앱 서브트리 OID 전용 검증 (scope 지정)
    public func verifyApp(scope: String, subtreeOID: String, rulesetDigest: String) throws -> VerificationResult {
        guard let appReceipt = try database.getAppReceipt(scope: scope, subtreeOID: subtreeOID, rulesetDigest: rulesetDigest) else {
            return .notFound
        }
        guard appReceipt.verdict == "PASS" && appReceipt.violationsCount == 0 else {
            return .invalid(
                reason: "App scope '\(scope)' (subtree '\(subtreeOID)') verdict is '\(appReceipt.verdict)' with \(appReceipt.violationsCount) violation(s)",
                violationsCount: appReceipt.violationsCount
            )
        }
        return .valid(Receipt(appTree: appReceipt))
    }
}
