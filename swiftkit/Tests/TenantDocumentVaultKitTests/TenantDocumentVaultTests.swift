import XCTest
import CryptoKit
@testable import TenantDocumentVaultKit

final class TenantDocumentVaultTests: XCTestCase {
    private var tempDirectory: URL?

    override func setUpWithError() throws {
        try super.setUpWithError()
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TenantDocumentVaultTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tempDirectory = dir
    }

    override func tearDownWithError() throws {
        if let tempDirectory, FileManager.default.fileExists(atPath: tempDirectory.path) {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        try super.tearDownWithError()
    }

    private func createDummyFile(name: String, content: String) throws -> URL {
        let tempDir = try XCTUnwrap(tempDirectory)
        let fileURL = tempDir.appendingPathComponent(name)
        let data = try XCTUnwrap(content.data(using: .utf8))
        try data.write(to: fileURL)
        return fileURL
    }

    func testTenantDocumentKindProperties() {
        XCTAssertEqual(TenantDocumentKind.businessLicense.displayName, "사업자등록증")
        XCTAssertNil(TenantDocumentKind.businessLicense.defaultValidityDays)

        XCTAssertEqual(TenantDocumentKind.corporateSealCert.displayName, "법인인감증명서")
        XCTAssertEqual(TenantDocumentKind.corporateSealCert.defaultValidityDays, 90)

        XCTAssertEqual(TenantDocumentKind.bankBook.displayName, "통장사본")
        XCTAssertNil(TenantDocumentKind.bankBook.defaultValidityDays)

        XCTAssertEqual(TenantDocumentKind.shareholdersRegister.displayName, "주주명부")
        XCTAssertNil(TenantDocumentKind.shareholdersRegister.defaultValidityDays)

        XCTAssertEqual(TenantDocumentKind.taxCleanCert.displayName, "국세/지방세 납세증명서")
        XCTAssertEqual(TenantDocumentKind.taxCleanCert.defaultValidityDays, 30)

        XCTAssertEqual(TenantDocumentKind.healthInsuranceCert.displayName, "건강보험자격득실확인서")
        XCTAssertEqual(TenantDocumentKind.healthInsuranceCert.defaultValidityDays, 90)
    }

    func testStoreAndCASVerification() throws {
        let tempDir = try XCTUnwrap(tempDirectory)
        let vault = TenantDocumentVault(tenantID: "tenant-corp", rootDirectory: tempDir)
        let sampleContent = "Sample Business License PDF content"
        let sampleFile = try createDummyFile(name: "license.pdf", content: sampleContent)

        let record = try vault.store(fileURL: sampleFile, kind: .businessLicense)

        // 해시 계산 검증
        let contentData = try XCTUnwrap(sampleContent.data(using: .utf8))
        let expectedDigest = SHA256.hash(data: contentData)
        let expectedHash = expectedDigest.map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(record.assetHash, expectedHash)
        XCTAssertEqual(record.kind, .businessLicense)
        XCTAssertEqual(record.originalName, "license.pdf")
        XCTAssertEqual(record.tenantID, "tenant-corp")
        XCTAssertNil(record.expiresAt)
        XCTAssertFalse(record.isExpired)

        // CAS 파일 복사 및 사이드카 확인
        let objectFile = vault.objectsDirectory.appendingPathComponent("\(expectedHash).pdf")
        let sidecarFile = vault.objectsDirectory.appendingPathComponent("\(expectedHash).json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: objectFile.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sidecarFile.path))

        // assetURL lookup 검증
        let lookupURL = vault.assetURL(for: record)
        XCTAssertNotNil(lookupURL)
        XCTAssertEqual(lookupURL?.lastPathComponent, "\(expectedHash).pdf")

        // records.json 확인
        let all = try vault.allRecords()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.id, record.id)
    }

    func testValidityCalculationAndExpiration() throws {
        let tempDir = try XCTUnwrap(tempDirectory)
        let vault = TenantDocumentVault(tenantID: "tenant-validity", rootDirectory: tempDir)
        let now = Date()
        let calendar = Calendar.current

        // 1. 법인인감 (기본 90일, 오늘 발급)
        let sealFile = try createDummyFile(name: "seal.pdf", content: "Corporate Seal")
        let sealRecord = try vault.store(
            fileURL: sealFile,
            kind: .corporateSealCert,
            issuedAt: now
        )
        let expectedSealExpiry = try XCTUnwrap(calendar.date(byAdding: .day, value: 90, to: now))
        let sealExpiresAt = try XCTUnwrap(sealRecord.expiresAt)
        XCTAssertEqual(
            calendar.startOfDay(for: sealExpiresAt),
            calendar.startOfDay(for: expectedSealExpiry)
        )
        XCTAssertFalse(sealRecord.isExpired)
        XCTAssertEqual(sealRecord.daysRemaining(from: now), 90)

        // 2. 국세 납세증명서 (기본 30일, 35일 전 발급 -> 만료됨)
        let pastDate = try XCTUnwrap(calendar.date(byAdding: .day, value: -35, to: now))
        let taxFile = try createDummyFile(name: "tax.pdf", content: "Tax Clearance")
        let taxRecord = try vault.store(
            fileURL: taxFile,
            kind: .taxCleanCert,
            issuedAt: pastDate
        )
        XCTAssertTrue(taxRecord.isExpired)
        let remainingDays = try XCTUnwrap(taxRecord.daysRemaining(from: now))
        XCTAssertLessThan(remainingDays, 0)

        // 3. 사용자 정의 validityDays 오버라이드 (15일)
        let customFile = try createDummyFile(name: "custom.pdf", content: "Custom Validity")
        let customRecord = try vault.store(
            fileURL: customFile,
            kind: .healthInsuranceCert,
            issuedAt: now,
            validityDays: 15
        )
        let expectedCustomExpiry = try XCTUnwrap(calendar.date(byAdding: .day, value: 15, to: now))
        let customExpiresAt = try XCTUnwrap(customRecord.expiresAt)
        XCTAssertEqual(
            calendar.startOfDay(for: customExpiresAt),
            calendar.startOfDay(for: expectedCustomExpiry)
        )
        XCTAssertEqual(customRecord.daysRemaining(from: now), 15)

        // 4. validRecords 검증
        let validRecords = try vault.validRecords()
        let validIDs = validRecords.map(\.id)
        XCTAssertTrue(validIDs.contains(sealRecord.id))
        XCTAssertTrue(validIDs.contains(customRecord.id))
        XCTAssertFalse(validIDs.contains(taxRecord.id))
    }

    func testLatestRecordIdempotency() throws {
        let tempDir = try XCTUnwrap(tempDirectory)
        let vault = TenantDocumentVault(tenantID: "tenant-latest", rootDirectory: tempDir)
        let calendar = Calendar.current
        let baseDate = Date()

        let file1 = try createDummyFile(name: "bank1.pdf", content: "Bank Copy 1")
        let date1 = try XCTUnwrap(calendar.date(byAdding: .day, value: -10, to: baseDate))
        _ = try vault.store(fileURL: file1, kind: .bankBook, issuedAt: date1)

        let file2 = try createDummyFile(name: "bank2.pdf", content: "Bank Copy 2 (Newer)")
        let date2 = try XCTUnwrap(calendar.date(byAdding: .day, value: -2, to: baseDate))
        let record2 = try vault.store(fileURL: file2, kind: .bankBook, issuedAt: date2)

        // 최신 조회
        let latest1 = try vault.latestRecord(for: .bankBook)
        XCTAssertEqual(latest1?.id, record2.id)

        // 과거 서류를 뒤늦게 추가 등록해도 latest는 date2의 record2이어야 함
        let fileOld = try createDummyFile(name: "bank_old.pdf", content: "Bank Copy Very Old")
        let dateOld = try XCTUnwrap(calendar.date(byAdding: .day, value: -30, to: baseDate))
        _ = try vault.store(fileURL: fileOld, kind: .bankBook, issuedAt: dateOld)

        // 멱등적 조회 확인
        let latest2 = try vault.latestRecord(for: .bankBook)
        XCTAssertEqual(latest2?.id, record2.id)

        let latest3 = try vault.latestRecord(for: .bankBook)
        XCTAssertEqual(latest3?.id, record2.id)

        // 등록된 적 없는 kind 조회 시 nil
        let nonExistent = try vault.latestRecord(for: .shareholdersRegister)
        XCTAssertNil(nonExistent)
    }

    func testDefaultRootDirectoryFromStateRootKit() {
        let vault = TenantDocumentVault(tenantID: "tenant:acme")
        XCTAssertTrue(vault.rootDirectory.path.contains(".tenants/acme/documents"))
    }
}
