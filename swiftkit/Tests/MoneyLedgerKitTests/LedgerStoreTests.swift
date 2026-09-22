import XCTest
import MoneyLedgerVaultKit
import MoneyLedgerModels
@testable import MoneyLedgerStoreKit

final class LedgerStoreTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ledger-tests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
    }

    private func makeStore() throws -> LedgerStore {
        try LedgerStore(url: tempDir.appendingPathComponent("ledger.sqlite"))
    }

    private func makeTransaction(
        date: String = "2026-08-04",
        amount: Int64 = -15000,
        accountID: String? = "acct-1",
        description: String = "테스트 거래",
        occurrence: Int = 1
    ) -> MoneyTransaction {
        let hash = ContentHash.transactionHash(
            date: date, time: nil, amountMinor: amount, currency: "KRW",
            instrumentID: accountID ?? "", description: description,
            balanceAfterMinor: nil, occurrence: occurrence
        )
        return MoneyTransaction(
            date: date, amountMinor: amount, accountID: accountID,
            description: description, contentHash: hash
        )
    }

    func testAccountCRUD() async throws {
        let store = try makeStore()
        let account = MoneyAccount(name: "주거래", bank: "신한", last4: "1234", purpose: "사업 운영비")
        try await store.save(account: account)

        // createdAt 은 ISO8601 왕복에서 초 단위로 절삭되므로 필드 단위로 비교한다.
        let listed = try await store.accounts()
        XCTAssertEqual(listed.map(\.id), [account.id])
        XCTAssertEqual(listed.first?.name, "주거래")
        XCTAssertEqual(listed.first?.bank, "신한")

        // id 접두사 조회
        let byPrefix = try await store.account(idPrefix: String(account.id.prefix(8)))
        XCTAssertEqual(byPrefix.id, account.id)

        // 이름 해석
        let byName = try await store.resolveAccount("주거래")
        XCTAssertEqual(byName.id, account.id)

        // 갱신(upsert)
        var updated = account
        updated.purpose = "급여 계좌"
        try await store.save(account: updated)
        let reloaded = try await store.account(idPrefix: account.id)
        XCTAssertEqual(reloaded.purpose, "급여 계좌")

        // 아카이브 필터
        updated.archived = true
        try await store.save(account: updated)
        let visible = try await store.accounts()
        XCTAssertTrue(visible.isEmpty)
        let all = try await store.accounts(includeArchived: true)
        XCTAssertEqual(all.count, 1)
    }

    func testAmbiguousPrefixThrows() async throws {
        let store = try makeStore()
        try await store.save(account: MoneyAccount(id: "aaa1", name: "A", bank: "B"))
        try await store.save(account: MoneyAccount(id: "aaa2", name: "C", bank: "D"))
        do {
            _ = try await store.account(idPrefix: "aaa")
            XCTFail("expected ambiguousID")
        } catch let error as LedgerStoreError {
            XCTAssertEqual(error, .ambiguousID("aaa"))
        }
    }

    func testMissingIDThrowsNotFound() async throws {
        let store = try makeStore()
        do {
            _ = try await store.account(idPrefix: "nope")
            XCTFail("expected notFound")
        } catch let error as LedgerStoreError {
            XCTAssertEqual(error, .notFound("nope"))
        }
    }

    func testAccountDeleteBlockedByTransactions() async throws {
        let store = try makeStore()
        let account = MoneyAccount(name: "주거래", bank: "신한")
        try await store.save(account: account)
        _ = try await store.insert(transaction: makeTransaction(accountID: account.id))

        do {
            try await store.deleteAccount(id: account.id)
            XCTFail("expected referencedByTransactions")
        } catch let error as LedgerStoreError {
            XCTAssertEqual(error, .referencedByTransactions(id: account.id, count: 1))
        }
    }

    func testTransactionDuplicateIsIdempotent() async throws {
        let store = try makeStore()
        let tx = makeTransaction()
        let first = try await store.insert(transaction: tx)
        XCTAssertFalse(first.duplicate)

        // 같은 내용(같은 해시)의 새 객체 — id 는 달라도 중복으로 잡혀야 한다.
        let replay = makeTransaction()
        let second = try await store.insert(transaction: replay)
        XCTAssertTrue(second.duplicate)
        XCTAssertEqual(second.transaction.id, tx.id)  // 기존 행 반환

        let count = try await store.transactionCount()
        XCTAssertEqual(count, 1)
    }

    func testTransactionQueryFilters() async throws {
        let store = try makeStore()
        _ = try await store.insert(transaction: makeTransaction(date: "2026-07-15", description: "7월 거래"))
        _ = try await store.insert(transaction: makeTransaction(date: "2026-08-01", description: "8월 거래 A"))
        _ = try await store.insert(transaction: makeTransaction(date: "2026-08-20", amount: 300_000, description: "8월 입금"))

        let august = try await store.transactions(
            TransactionQuery(fromDate: "2026-08-01", toDate: "2026-08-99")
        )
        XCTAssertEqual(august.count, 2)
        // 최신 날짜 우선 정렬
        XCTAssertEqual(august.first?.date, "2026-08-20")

        let limited = try await store.transactions(TransactionQuery(limit: 1))
        XCTAssertEqual(limited.count, 1)
    }

    func testSubscriptionStatusFilter() async throws {
        let store = try makeStore()
        try await store.save(subscription: MoneySubscription(name: "Claude", amountMinor: 3000, currency: "USD"))
        var cancelled = MoneySubscription(name: "Netflix", amountMinor: 17000)
        cancelled.status = .cancelled
        try await store.save(subscription: cancelled)

        let active = try await store.subscriptions(status: .active)
        XCTAssertEqual(active.map(\.name), ["Claude"])
        let all = try await store.subscriptions()
        XCTAssertEqual(all.count, 2)
    }

    func testImportBatchUndo() async throws {
        let store = try makeStore()
        let batchID = "batch-1"
        var tx1 = makeTransaction(description: "배치 거래 1")
        tx1.importBatchID = batchID
        var tx2 = makeTransaction(description: "배치 거래 2")
        tx2.importBatchID = batchID
        _ = try await store.insert(transaction: tx1)
        _ = try await store.insert(transaction: tx2)
        _ = try await store.insert(transaction: makeTransaction(description: "배치 밖 거래"))
        try await store.save(batch: ImportBatch(
            id: batchID, sourceFile: "/tmp/a.csv", encoding: "utf8",
            mapping: "date=1", inserted: 2, duplicates: 0, errorCount: 0
        ))

        let removed = try await store.undoImportBatch(id: batchID)
        XCTAssertEqual(removed, 2)
        let remaining = try await store.transactionCount()
        XCTAssertEqual(remaining, 1)
        let batches = try await store.importBatches()
        XCTAssertTrue(batches.isEmpty)
    }

    func testCategoryUpdatePreservesHash() async throws {
        let store = try makeStore()
        let tx = makeTransaction()
        _ = try await store.insert(transaction: tx)
        var updated = try await store.transaction(idPrefix: tx.id)
        updated.category = "식비"
        try await store.update(transaction: updated)
        let reloaded = try await store.transaction(idPrefix: tx.id)
        XCTAssertEqual(reloaded.category, "식비")
        XCTAssertEqual(reloaded.contentHash, tx.contentHash)
    }

    func testTimeSortWithinDay() async throws {
        let store = try makeStore()
        var early = makeTransaction(description: "아침")
        early.time = "08:00:00"
        early.contentHash = ContentHash.transactionHash(
            date: early.date, time: early.time, amountMinor: early.amountMinor,
            currency: "KRW", instrumentID: "acct-1", description: "아침", balanceAfterMinor: nil
        )
        var late = makeTransaction(description: "저녁")
        late.time = "20:00:00"
        late.contentHash = ContentHash.transactionHash(
            date: late.date, time: late.time, amountMinor: late.amountMinor,
            currency: "KRW", instrumentID: "acct-1", description: "저녁", balanceAfterMinor: nil
        )
        _ = try await store.insert(transaction: early)
        _ = try await store.insert(transaction: late)
        let listed = try await store.transactions()
        XCTAssertEqual(listed.map(\.description), ["저녁", "아침"])
    }

    func testTransactionBusinessIDRoundTripAndFilter() async throws {
        let store = try makeStore()
        var tagged = makeTransaction(description: "달숲 매출")
        tagged.businessID = "biz-dalsoop"
        _ = try await store.insert(transaction: tagged)
        _ = try await store.insert(transaction: makeTransaction(description: "귀속 없음"))

        let filtered = try await store.transactions(TransactionQuery(businessID: "biz-dalsoop"))
        XCTAssertEqual(filtered.map(\.description), ["달숲 매출"])
        XCTAssertEqual(filtered.first?.businessID, "biz-dalsoop")
        let all = try await store.transactions()
        XCTAssertEqual(all.count, 2)

        // 귀속 해제 — 컬럼과 payload 가 같이 비워져 필터에서 빠진다. 해시는 불변.
        var cleared = try await store.transaction(idPrefix: tagged.id)
        cleared.businessID = nil
        try await store.update(transaction: cleared)
        let afterClear = try await store.transactions(TransactionQuery(businessID: "biz-dalsoop"))
        XCTAssertTrue(afterClear.isEmpty)
        let reloaded = try await store.transaction(idPrefix: tagged.id)
        XCTAssertNil(reloaded.businessID)
        XCTAssertEqual(reloaded.contentHash, tagged.contentHash)
    }

    /// 옛 원장(business_id 컬럼·payload 키 없음)을 열면 컬럼이 덧붙고 기존 행은 nil 로 읽힌다.
    func testLegacyLedgerGainsBusinessColumn() async throws {
        try LegacyLedgerFixture.write(
            to: tempDir.appendingPathComponent("ledger.sqlite"), transactionID: "legacy-1"
        )
        let store = try makeStore()
        let version = try await store.storedSchemaVersion()
        XCTAssertEqual(version, LedgerStore.schemaVersion)
        let legacy = try await store.transaction(idPrefix: "legacy-1")
        XCTAssertNil(legacy.businessID)
        XCTAssertEqual(legacy.description, "옛 거래")

        var tagged = makeTransaction(description: "새 거래")
        tagged.businessID = "biz-1"
        _ = try await store.insert(transaction: tagged)
        let filtered = try await store.transactions(TransactionQuery(businessID: "biz-1"))
        XCTAssertEqual(filtered.map(\.description), ["새 거래"])

        // 두 번째 열기도 멱등 — ALTER 가 다시 돌지 않는다.
        let reopened = try makeStore()
        let count = try await reopened.transactionCount()
        XCTAssertEqual(count, 2)
    }

    /// payload JSON 에 businessID 키가 없는 옛 행은 nil 로 디코딩된다(필드 추가 = 옵셔널 계약).
    func testLegacyPayloadDecodesWithoutBusinessID() throws {
        let json = """
        {"id":"t1","date":"2026-01-15","amountMinor":-1000,"currency":"KRW","description":"옛 거래",\
        "contentHash":"h","createdAt":"2026-01-15T00:00:00Z"}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let tx = try decoder.decode(MoneyTransaction.self, from: Data(json.utf8))
        XCTAssertNil(tx.businessID)
        XCTAssertEqual(tx.id, "t1")
    }
}
