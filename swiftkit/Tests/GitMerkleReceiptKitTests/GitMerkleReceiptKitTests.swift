import XCTest
import Foundation
@testable import GitMerkleReceiptKit
import DoctorContract

final class GitMerkleReceiptKitTests: XCTestCase {
    private var tempDir: URL?
    private var dbPath: String?

    override func setUpWithError() throws {
        try super.setUpWithError()
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitMerkleReceiptKitTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.tempDir = dir
        self.dbPath = dir.appendingPathComponent("receipts.db").path
    }

    override func tearDownWithError() throws {
        if let dir = tempDir, FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.removeItem(at: dir)
        }
        try super.tearDownWithError()
    }

    private func requireDBPath() throws -> String {
        guard let dbPath else {
            throw XCTSkip("Test database path is uninitialized")
        }
        return dbPath
    }

    // MARK: - GitMerkleTreeScanner Tests

    func testTreeScannerRootAndSubtree() async throws {
        let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let scanner = GitMerkleTreeScanner(repositoryRoot: repoRoot)

        let start = CFAbsoluteTimeGetCurrent()
        let rootOID = try await scanner.scanRootTree()
        let duration = CFAbsoluteTimeGetCurrent() - start

        XCTAssertFalse(rootOID.isEmpty)
        XCTAssertTrue(GitMerkleTreeScanner.isValidOID(rootOID), "OID should be 40 or 64 hex characters: \(rootOID)")
        _ = duration

        // swiftkit subtree 스캔
        let subtreeOID = try await scanner.scanSubtree(prefix: "swiftkit")
        XCTAssertFalse(subtreeOID.isEmpty)
        XCTAssertTrue(GitMerkleTreeScanner.isValidOID(subtreeOID))

        // 복수 서브트리 병렬 스캔
        let multiResults = try await scanner.scanSubtrees(prefixes: ["swiftkit", "swiftkit/Sources"])
        XCTAssertEqual(multiResults.count, 2)
        XCTAssertEqual(multiResults["swiftkit"], subtreeOID)
        XCTAssertNotNil(multiResults["swiftkit/Sources"])
    }

    func testTreeScannerNonexistentPrefixThrows() async {
        let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let scanner = GitMerkleTreeScanner(repositoryRoot: repoRoot)

        do {
            _ = try await scanner.scanSubtree(prefix: "nonexistent_directory_xyz_98765")
            XCTFail("Should have thrown prefixNotFound")
        } catch let GitMerkleTreeError.prefixNotFound(prefix) {
            XCTAssertEqual(prefix, "nonexistent_directory_xyz_98765")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - ReceiptLedgerDatabase Tests

    func testDatabaseAppTreeReceiptCRUD() throws {
        let db = try requireDBPath()
        let database = try ReceiptLedgerDatabase(databasePath: db)

        let sampleReceipt = AppTreeReceipt(
            scope: "apps/test-app-swift",
            subtreeOID: "67344c1d0809cc1742e60416f8752b97882b3312",
            rulesetDigest: "abc123rulesetdigest",
            verdict: "PASS",
            violationsCount: 0,
            byRuleJSON: "{\"line-length\": 0}"
        )

        // 1. 기록
        try database.recordAppReceipt(sampleReceipt)

        // 2. scope + subtreeOID + rulesetDigest 조회
        let retrieved = try database.getAppReceipt(
            scope: "apps/test-app-swift",
            subtreeOID: "67344c1d0809cc1742e60416f8752b97882b3312",
            rulesetDigest: "abc123rulesetdigest"
        )
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.scope, "apps/test-app-swift")
        XCTAssertEqual(retrieved?.verdict, "PASS")
        XCTAssertEqual(retrieved?.violationsCount, 0)

        // 3. subtreeOID + rulesetDigest 인덱스 조회
        let indexed = try database.getAppReceipt(
            subtreeOID: "67344c1d0809cc1742e60416f8752b97882b3312",
            rulesetDigest: "abc123rulesetdigest"
        )
        XCTAssertEqual(indexed?.scope, "apps/test-app-swift")

        // 4. UPSERT 덮어쓰기 테스트
        let updatedReceipt = AppTreeReceipt(
            scope: "apps/test-app-swift",
            subtreeOID: "67344c1d0809cc1742e60416f8752b97882b3312",
            rulesetDigest: "abc123rulesetdigest",
            verdict: "FAIL",
            violationsCount: 3,
            byRuleJSON: "{\"line-length\": 3}"
        )
        try database.recordAppReceipt(updatedReceipt)

        let retrievedUpdated = try database.getAppReceipt(
            scope: "apps/test-app-swift",
            subtreeOID: "67344c1d0809cc1742e60416f8752b97882b3312",
            rulesetDigest: "abc123rulesetdigest"
        )
        XCTAssertEqual(retrievedUpdated?.verdict, "FAIL")
        XCTAssertEqual(retrievedUpdated?.violationsCount, 3)

        // 5. 전체 조회
        let all = try database.getAllAppReceipts(rulesetDigest: "abc123rulesetdigest")
        XCTAssertEqual(all.count, 1)
    }

    func testDatabaseRepoRootReceiptCRUD() throws {
        let db = try requireDBPath()
        let database = try ReceiptLedgerDatabase(databasePath: db)

        let rootReceipt = RepoRootReceipt(
            rootTreeOID: "2c7ae11102a0a38d61c81f1f25df80fe0b175c69",
            rulesetDigest: "ruleset-v1-hash",
            totalViolations: 0,
            byRuleJSON: "{}",
            byAppJSON: "{}"
        )

        try database.recordRepoRootReceipt(rootReceipt)

        let retrieved = try database.getRepoRootReceipt(
            rootTreeOID: "2c7ae11102a0a38d61c81f1f25df80fe0b175c69",
            rulesetDigest: "ruleset-v1-hash"
        )
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.totalViolations, 0)
        XCTAssertEqual(retrieved?.rootTreeOID, "2c7ae11102a0a38d61c81f1f25df80fe0b175c69")
    }

    // MARK: - ReceiptVerifier Tests & SLA Benchmark

    func testReceiptVerifierValidAndInvalid() throws {
        let db = try requireDBPath()
        let database = try ReceiptLedgerDatabase(databasePath: db)
        let verifier = ReceiptVerifier(database: database)

        let rootTreeOID = "2c7ae11102a0a38d61c81f1f25df80fe0b175c69"
        let rulesetDigest = "digest-prod-2026"

        // 1. 영수증 없음 -> notFound
        let notFoundResult = try verifier.verify(treeOID: rootTreeOID, rulesetDigest: rulesetDigest)
        XCTAssertEqual(notFoundResult, .notFound)

        // 2. 합격 영수증 기록
        let validReceipt = RepoRootReceipt(
            rootTreeOID: rootTreeOID,
            rulesetDigest: rulesetDigest,
            totalViolations: 0,
            byRuleJSON: "{}",
            byAppJSON: "{}"
        )
        try database.recordRepoRootReceipt(validReceipt)

        // 3. 검증 실행 -> .valid(Receipt)
        let validResult = try verifier.verify(treeOID: rootTreeOID, rulesetDigest: rulesetDigest)
        guard case .valid(let receipt) = validResult else {
            return XCTFail("Expected valid receipt, got \(validResult)")
        }
        XCTAssertEqual(receipt.treeOID, rootTreeOID)
        XCTAssertEqual(receipt.violationsCount, 0)
        XCTAssertEqual(receipt.verdict, "PASS")

        // 4. 불합격 영수증으로 교체 -> .invalid
        let failingReceipt = RepoRootReceipt(
            rootTreeOID: rootTreeOID,
            rulesetDigest: rulesetDigest,
            totalViolations: 4,
            byRuleJSON: "{\"line-length\": 4}",
            byAppJSON: "{}"
        )
        try database.recordRepoRootReceipt(failingReceipt)

        let invalidResult = try verifier.verify(treeOID: rootTreeOID, rulesetDigest: rulesetDigest)
        guard case .invalid(let reason, let violationsCount) = invalidResult else {
            return XCTFail("Expected invalid result, got \(invalidResult)")
        }
        XCTAssertEqual(violationsCount, 4)
        XCTAssertTrue(reason.contains("4"))
    }

    func testReceiptVerifierSubtreeVerification() throws {
        let db = try requireDBPath()
        let database = try ReceiptLedgerDatabase(databasePath: db)
        let verifier = ReceiptVerifier(database: database)

        let subtreeOID = "1234567890abcdef1234567890abcdef12345678"
        let digest = "digest-v2"

        let appReceipt = AppTreeReceipt(
            scope: "apps/my-app",
            subtreeOID: subtreeOID,
            rulesetDigest: digest,
            verdict: "PASS",
            violationsCount: 0,
            byRuleJSON: "{}"
        )
        try database.recordAppReceipt(appReceipt)

        let result = try verifier.verify(treeOID: subtreeOID, rulesetDigest: digest)
        guard case .valid(let receipt) = result else {
            return XCTFail("Expected valid subtree receipt, got \(result)")
        }
        XCTAssertTrue(receipt.isAppTree)
        XCTAssertEqual(receipt.scope, "apps/my-app")
    }

    func testVerificationSpeedSLA() throws {
        let db = try requireDBPath()
        let database = try ReceiptLedgerDatabase(databasePath: db)
        let verifier = ReceiptVerifier(database: database)

        let treeOID = "2c7ae11102a0a38d61c81f1f25df80fe0b175c69"
        let digest = "benchmark-digest"

        let validReceipt = RepoRootReceipt(
            rootTreeOID: treeOID,
            rulesetDigest: digest,
            totalViolations: 0,
            byRuleJSON: "{}",
            byAppJSON: "{}"
        )
        try database.recordRepoRootReceipt(validReceipt)

        let iterations = 100
        let start = CFAbsoluteTimeGetCurrent()
        for _ in 0..<iterations {
            let res = try verifier.verify(treeOID: treeOID, rulesetDigest: digest)
            guard case .valid = res else {
                XCTFail("Verification should succeed")
                break
            }
        }
        let totalTime = CFAbsoluteTimeGetCurrent() - start
        let avgTime = totalTime / Double(iterations)

        XCTAssertLessThan(avgTime, 0.005, "Average verify time must be < 5ms (actual: \(avgTime * 1000)ms)")
    }

    // MARK: - ReceiptLedger & ReceiptDoctorProvider Tests

    func testReceiptLedgerIssueAndQuery() throws {
        let db = try requireDBPath()
        let ledger = try ReceiptLedger(databasePath: db)

        let targetPath = "apps/sample-app"
        let treeOID = "4b825dc642cb6eb9a060e54bf8d69288fbee4904"
        let rulesetDigest = "rule-sha256-abc"
        let toolchainHash = "toolchain-sha256-xyz"

        // 1) Verify missing
        let initialResult = try ledger.verifyReceipt(
            targetPath: targetPath,
            treeOID: treeOID,
            rulesetDigest: rulesetDigest,
            toolchainHash: toolchainHash
        )
        XCTAssertEqual(initialResult, .missing)

        // 2) Issue passing receipt
        let receipt = AnalysisReceipt(
            targetPath: targetPath,
            treeOID: treeOID,
            rulesetDigest: rulesetDigest,
            toolchainHash: toolchainHash,
            verdict: .pass,
            violationCount: 0,
            findingsData: nil,
            durationMs: 142.5
        )
        try ledger.issueReceipt(receipt)

        // 3) Query receipt
        let queried = try ledger.queryReceipt(
            targetPath: targetPath,
            treeOID: treeOID,
            rulesetDigest: rulesetDigest,
            toolchainHash: toolchainHash
        )
        XCTAssertNotNil(queried)
        XCTAssertEqual(queried?.verdict, .pass)
        XCTAssertEqual(queried?.violationCount, 0)
        XCTAssertEqual(queried?.targetPath, targetPath)

        // 4) Verify valid
        let verifyResult = try ledger.verifyReceipt(
            targetPath: targetPath,
            treeOID: treeOID,
            rulesetDigest: rulesetDigest,
            toolchainHash: toolchainHash
        )
        guard case let .valid(validReceipt) = verifyResult else {
            XCTFail("Expected valid receipt result")
            return
        }
        XCTAssertEqual(validReceipt.verdict, .pass)
    }

    func testReceiptDoctorProvider() async throws {
        let db = try requireDBPath()
        let ledger = try ReceiptLedger(databasePath: db)
        let passingPath = "apps/passing-app"
        let failingPath = "apps/failing-app"
        let missingPath = "apps/missing-app"

        let treeOID = "deadbeef1234567890abcdef"
        let rulesetDigest = "digest-1"
        let toolchainHash = "toolchain-1"

        try ledger.issueReceipt(AnalysisReceipt(
            targetPath: passingPath,
            treeOID: treeOID,
            rulesetDigest: rulesetDigest,
            toolchainHash: toolchainHash,
            verdict: .pass,
            violationCount: 0,
            durationMs: 50.0
        ))

        try ledger.issueReceipt(AnalysisReceipt(
            targetPath: failingPath,
            treeOID: treeOID,
            rulesetDigest: rulesetDigest,
            toolchainHash: toolchainHash,
            verdict: .fail,
            violationCount: 2,
            durationMs: 120.0
        ))

        let provider = ReceiptDoctorProvider(
            ledger: ledger,
            targetPaths: [passingPath, failingPath, missingPath],
            rulesetDigest: rulesetDigest,
            toolchainHash: toolchainHash,
            treeOIDProvider: { _ in treeOID }
        )

        let findings = await provider.run()
        XCTAssertEqual(findings.count, 2)

        let failFinding = findings.first { $0.subject == failingPath }
        XCTAssertNotNil(failFinding)
        XCTAssertEqual(failFinding?.severity, .fail)

        let missingFinding = findings.first { $0.subject == missingPath }
        XCTAssertNotNil(missingFinding)
        XCTAssertEqual(missingFinding?.severity, .warn)
    }
}
