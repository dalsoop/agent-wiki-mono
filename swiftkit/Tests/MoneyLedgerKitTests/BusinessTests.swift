import XCTest
import MoneyLedgerVaultKit
import MoneyLedgerStoreKit
import MoneyLedgerModels
@testable import MoneyLedgerModels

final class BusinessNumberTests: XCTestCase {
    func testChecksumVectors() {
        // 실존 공개 번호(삼성전자 124-81-00998) 포함 — 체크섬 알고리즘 회귀 가드.
        XCTAssertTrue(BusinessNumber.isValid("124-81-00998"))
        XCTAssertTrue(BusinessNumber.isValid("1234567891"))
        XCTAssertFalse(BusinessNumber.isValid("1234567890"))
        XCTAssertFalse(BusinessNumber.isValid("123-45"))
        XCTAssertFalse(BusinessNumber.isValid(""))
    }

    func testFormatAndDigits() {
        XCTAssertEqual(BusinessNumber.format("1248100998"), "124-81-00998")
        XCTAssertEqual(BusinessNumber.digits("124-81-00998"), "1248100998")
        // 10자리가 아니면 입력 유지
        XCTAssertEqual(BusinessNumber.format("12345"), "12345")
    }
}

final class BusinessStoreTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ledger-biz-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
    }

    private func makeContext() -> LedgerContext {
        LedgerContext(scope: .business, databaseURL: tempDir.appendingPathComponent("ledger.sqlite"))
    }

    func testBusinessCRUD() async throws {
        let store = try LedgerStore(context: makeContext())
        let business = BusinessProfile(
            name: "달숲",
            registrationNumber: "123-45-67891",
            representative: "윤정한",
            businessType: "정보통신업",
            businessItem: "소프트웨어 개발"
        )
        try await store.save(business: business)

        // 하이픈은 저장 시 제거된다
        let loaded = try await store.business(idPrefix: business.id)
        XCTAssertEqual(loaded.registrationNumber, "1234567891")

        // 이름 해석
        let byName = try await store.resolveBusiness("달숲")
        XCTAssertEqual(byName.id, business.id)

        // 아카이브 필터
        var archived = loaded
        archived.archived = true
        try await store.save(business: archived)
        let visible = try await store.businesses()
        XCTAssertTrue(visible.isEmpty)
        let all = try await store.businesses(includeArchived: true)
        XCTAssertEqual(all.count, 1)
    }

    func testAttachmentLifecycle() async throws {
        let context = makeContext()
        let store = try LedgerStore(context: context)
        let files = AttachmentStore(context: context)
        let business = BusinessProfile(name: "달숲")
        try await store.save(business: business)

        // 원본 파일 준비
        let source = tempDir.appendingPathComponent("사업자등록증.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: source)

        let record = try files.importFile(ownerKind: .business, ownerID: business.id, sourceURL: source)
        try await store.insert(attachment: record)

        // 파일이 저장소로 복사됐다
        let stored = files.fileURL(for: record)
        XCTAssertTrue(FileManager.default.fileExists(atPath: stored.path))
        XCTAssertEqual(record.originalName, "사업자등록증.png")
        XCTAssertTrue(stored.path.hasSuffix(".png"))

        let listed = try await store.attachments(ownerKind: .business, ownerID: business.id)
        XCTAssertEqual(listed.map(\.id), [record.id])

        // detach
        try await store.deleteAttachment(id: record.id)
        files.removeFile(for: record)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stored.path))
        let empty = try await store.attachments(ownerKind: .business, ownerID: business.id)
        XCTAssertTrue(empty.isEmpty)
    }

    func testDeleteBusinessCascadesAttachmentRows() async throws {
        let context = makeContext()
        let store = try LedgerStore(context: context)
        let files = AttachmentStore(context: context)
        let business = BusinessProfile(name: "달숲")
        try await store.save(business: business)
        let source = tempDir.appendingPathComponent("doc.pdf")
        try Data("pdf".utf8).write(to: source)
        let record = try files.importFile(ownerKind: .business, ownerID: business.id, sourceURL: source)
        try await store.insert(attachment: record)

        let removed = try await store.deleteBusiness(id: business.id)
        XCTAssertEqual(removed.map(\.id), [record.id])
        let businesses = try await store.businesses(includeArchived: true)
        XCTAssertTrue(businesses.isEmpty)
        let orphans = try await store.attachments(ownerKind: .business, ownerID: business.id)
        XCTAssertTrue(orphans.isEmpty)
    }

    func testMissingSourceFileThrows() throws {
        let files = AttachmentStore(context: makeContext())
        XCTAssertThrowsError(
            try files.importFile(
                ownerKind: .business,
                ownerID: "x",
                sourceURL: tempDir.appendingPathComponent("없는파일.png")
            )
        )
    }
}
