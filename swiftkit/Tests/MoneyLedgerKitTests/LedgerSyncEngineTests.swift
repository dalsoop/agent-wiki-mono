import XCTest
import SQLite3
import MoneyLedgerModels
@testable import MoneyLedgerStoreKit

final class LedgerSyncEngineTests: XCTestCase {
    private var tempDir: URL = FileManager.default.temporaryDirectory

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ledger-sync-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeStore(name: String) throws -> LedgerStore {
        try LedgerStore(url: tempDir.appendingPathComponent("\(name).sqlite"))
    }

    func testTwoWayMergePreservesAccountsCardsSubscriptionsBudgetsAndTransactions() async throws {
        let localStore = try makeStore(name: "local")
        let remoteStore = try makeStore(name: "remote")

        // 1. 로컬에만 있는 데이터 생성
        let localAcc = MoneyAccount(id: "acc-local-1", name: "로컬통장", bank: "국민", last4: "1111")
        try await localStore.save(account: localAcc)

        let localCard = MoneyCard(id: "card-local-1", name: "로컬카드", issuer: "국민", last4: "2222", linkedAccountID: "acc-local-1")
        try await localStore.save(card: localCard)

        let localSub = MoneySubscription(id: "sub-local-1", name: "로컬구독", amountMinor: 9900, currency: "KRW", period: .monthly, status: .active)
        try await localStore.save(subscription: localSub)

        let localBudget = MoneyBudget(id: "budget-local-1", category: "식비", amountMinor: 500_000, currency: "KRW")
        try await localStore.save(budget: localBudget)

        let localTx = MoneyTransaction(
            date: "2026-09-01",
            amountMinor: -10000,
            accountID: "acc-local-1",
            description: "로컬 지출",
            contentHash: "hash-local-1"
        )
        _ = try await localStore.insert(transaction: localTx)

        // 2. 원격에만 있는 데이터 생성
        let remoteAcc = MoneyAccount(id: "acc-remote-1", name: "원격통장", bank: "신한", last4: "3333")
        try await remoteStore.save(account: remoteAcc)

        let remoteCard = MoneyCard(id: "card-remote-1", name: "원격카드", issuer: "신한", last4: "4444", linkedAccountID: "acc-remote-1")
        try await remoteStore.save(card: remoteCard)

        let remoteSub = MoneySubscription(id: "sub-remote-1", name: "원격구독", amountMinor: 14900, currency: "KRW", period: .monthly, status: .active)
        try await remoteStore.save(subscription: remoteSub)

        let remoteBudget = MoneyBudget(id: "budget-remote-1", category: "교통비", amountMinor: 150_000, currency: "KRW")
        try await remoteStore.save(budget: remoteBudget)

        let remoteTx = MoneyTransaction(
            id: "tx-remote-1",
            stamp: MoneyTransaction.Stamp(date: "2026-09-02"),
            amount: MoneyTransaction.Amount(amountMinor: -20000),
            parties: MoneyTransaction.Parties(accountID: "acc-remote-1", cardID: "card-remote-1"),
            narrative: MoneyTransaction.Narrative(description: "원격 지출"),
            contentHash: "hash-remote-1"
        )
        _ = try await remoteStore.insert(transaction: remoteTx)

        // 3. dry-run 시뮬레이션 검증
        let dryReport = try await LedgerSyncEngine.merge(from: remoteStore, into: localStore, dryRun: true)
        XCTAssertEqual(dryReport.accountsAdded, 1)
        XCTAssertEqual(dryReport.cardsAdded, 1)
        XCTAssertEqual(dryReport.subscriptionsAdded, 1)
        XCTAssertEqual(dryReport.budgetsAdded, 1)
        XCTAssertEqual(dryReport.transactionsAdded, 1)

        // dry-run 후 로컬 DB가 변경되지 않았는지 확인
        var localAccs = try await localStore.accounts(includeArchived: true)
        XCTAssertEqual(localAccs.count, 1)
        XCTAssertEqual(localAccs.first?.id, "acc-local-1")

        // 4. 실제 양방향 병합 실행 (원격 -> 로컬)
        let actualReport = try await LedgerSyncEngine.merge(from: remoteStore, into: localStore, dryRun: false)
        XCTAssertEqual(actualReport.accountsAdded, 1)
        XCTAssertEqual(actualReport.cardsAdded, 1)
        XCTAssertEqual(actualReport.subscriptionsAdded, 1)
        XCTAssertEqual(actualReport.budgetsAdded, 1)
        XCTAssertEqual(actualReport.transactionsAdded, 1)
        XCTAssertEqual(actualReport.totalEntitiesAdded, 5)

        // 5. 로컬 저장소가 완전체(Union)가 되었는지 검증
        localAccs = try await localStore.accounts(includeArchived: true)
        XCTAssertEqual(localAccs.count, 2)
        XCTAssertTrue(localAccs.contains(where: { $0.id == "acc-local-1" }))
        XCTAssertTrue(localAccs.contains(where: { $0.id == "acc-remote-1" }))

        let localCards = try await localStore.cards(includeArchived: true)
        XCTAssertEqual(localCards.count, 2)
        XCTAssertTrue(localCards.contains(where: { $0.id == "card-local-1" }))
        XCTAssertTrue(localCards.contains(where: { $0.id == "card-remote-1" }))

        let localSubs = try await localStore.subscriptions(includeArchived: true)
        XCTAssertEqual(localSubs.count, 2)
        XCTAssertTrue(localSubs.contains(where: { $0.id == "sub-local-1" }))
        XCTAssertTrue(localSubs.contains(where: { $0.id == "sub-remote-1" }))

        let localBudgets = try await localStore.budgets(month: nil)
        XCTAssertEqual(localBudgets.count, 2)
        XCTAssertTrue(localBudgets.contains(where: { $0.id == "budget-local-1" }))
        XCTAssertTrue(localBudgets.contains(where: { $0.id == "budget-remote-1" }))

        let localTxs = try await localStore.transactions(TransactionQuery())
        XCTAssertEqual(localTxs.count, 2)
        XCTAssertTrue(localTxs.contains(where: { $0.contentHash == "hash-local-1" }))
        XCTAssertTrue(localTxs.contains(where: { $0.contentHash == "hash-remote-1" }))

        // 6. 멱등성 검증 (동일 병합 재실행 시 0건 추가)
        let idempotentReport = try await LedgerSyncEngine.merge(from: remoteStore, into: localStore, dryRun: false)
        XCTAssertEqual(idempotentReport.accountsAdded, 0)
        XCTAssertEqual(idempotentReport.cardsAdded, 0)
        XCTAssertEqual(idempotentReport.subscriptionsAdded, 0)
        XCTAssertEqual(idempotentReport.budgetsAdded, 0)
        XCTAssertEqual(idempotentReport.transactionsAdded, 0)
        XCTAssertEqual(idempotentReport.totalEntitiesAdded, 0)

        // 7. 완전체 로컬 원장을 원격에 복제(Checkpoint Push 효과 검증)
        // 원격 저장소도 로컬과 동일하게 완전체가 되는지 검증
        let reverseReport = try await LedgerSyncEngine.merge(from: localStore, into: remoteStore, dryRun: false)
        XCTAssertEqual(reverseReport.accountsAdded, 1) // 로컬 계좌 1개 추가
        XCTAssertEqual(reverseReport.cardsAdded, 1)    // 로컬 카드 1개 추가
        XCTAssertEqual(reverseReport.subscriptionsAdded, 1) // 로컬 구독 1개 추가
        XCTAssertEqual(reverseReport.budgetsAdded, 1)       // 로컬 예산 1개 추가
        XCTAssertEqual(reverseReport.transactionsAdded, 1)  // 로컬 거래 1개 추가

        let remoteAccsFinal = try await remoteStore.accounts(includeArchived: true)
        XCTAssertEqual(remoteAccsFinal.count, 2)
        let remoteCardsFinal = try await remoteStore.cards(includeArchived: true)
        XCTAssertEqual(remoteCardsFinal.count, 2)
        let remoteSubsFinal = try await remoteStore.subscriptions(includeArchived: true)
        XCTAssertEqual(remoteSubsFinal.count, 2)
        let remoteBudgetsFinal = try await remoteStore.budgets(month: nil)
        XCTAssertEqual(remoteBudgetsFinal.count, 2)
        let remoteTxsFinal = try await remoteStore.transactions(TransactionQuery())
        XCTAssertEqual(remoteTxsFinal.count, 2)
    }

    func testTombstonePreventsZombieResurrection() async throws {
        let localStore = try makeStore(name: "local_zombie_test")
        let remoteStore = try makeStore(name: "remote_zombie_test")

        // 1. 공통 데이터가 양쪽에 존재
        let acc = MoneyAccount(id: "acc-shared-1", name: "공통통장", bank: "국민", last4: "1111")
        try await localStore.save(account: acc)
        try await remoteStore.save(account: acc)

        let tx = MoneyTransaction(
            id: "tx-shared-1",
            date: "2026-09-01",
            amountMinor: -10000,
            accountID: "acc-shared-1",
            description: "공통 지출",
            contentHash: "hash-shared-1"
        )
        _ = try await localStore.insert(transaction: tx)
        _ = try await remoteStore.insert(transaction: tx)

        // 2. 로컬에서 거래 및 계좌 삭제 -> 툼스톤 기록됨
        try await localStore.deleteTransaction(id: "tx-shared-1")
        try await localStore.deleteAccount(id: "acc-shared-1")

        let localAccsAfterDelete = try await localStore.accounts(includeArchived: true)
        XCTAssertEqual(localAccsAfterDelete.count, 0)
        let localTxsAfterDelete = try await localStore.transactions(TransactionQuery())
        XCTAssertEqual(localTxsAfterDelete.count, 0)
        let isAccTomb = try await localStore.isTombstoned(entityType: "account", entityID: "acc-shared-1")
        XCTAssertTrue(isAccTomb)
        let isTxTomb = try await localStore.isTombstoned(entityType: "transaction", entityID: "tx-shared-1")
        XCTAssertTrue(isTxTomb)
        let isHashTomb = try await localStore.isTombstoned(entityType: "transaction_hash", entityID: "hash-shared-1")
        XCTAssertTrue(isHashTomb)

        // 3. 원격에는 아직 살아있음
        let remoteAccsBefore = try await remoteStore.accounts(includeArchived: true)
        XCTAssertEqual(remoteAccsBefore.count, 1)
        let remoteTxsBefore = try await remoteStore.transactions(TransactionQuery())
        XCTAssertEqual(remoteTxsBefore.count, 1)

        // 4. 원격 -> 로컬 동기화 실행 (과거에는 단순 Union 병합으로 원격의 삭제된 엔티티가 로컬에 좀비로 부활했음)
        let report = try await LedgerSyncEngine.merge(from: remoteStore, into: localStore, dryRun: false)

        // 툼스톤으로 인해 원격 데이터가 로컬로 부활(추가)되지 않아야 함!
        XCTAssertEqual(report.accountsAdded, 0)
        XCTAssertEqual(report.transactionsAdded, 0)
        let localAccsAfterMerge = try await localStore.accounts(includeArchived: true)
        XCTAssertEqual(localAccsAfterMerge.count, 0, "로컬 계좌가 좀비로 부활해선 안 됨")
        let localTxsAfterMerge = try await localStore.transactions(TransactionQuery())
        XCTAssertEqual(localTxsAfterMerge.count, 0, "로컬 거래가 좀비로 부활해선 안 됨")

        // 5. 로컬 -> 원격 역방향 동기화 시 로컬의 툼스톤이 원격으로 전파되어 원격에서도 삭제되어야 함!
        let reverseReport = try await LedgerSyncEngine.merge(from: localStore, into: remoteStore, dryRun: false)
        XCTAssertEqual(reverseReport.accountsDeleted, 1)
        XCTAssertEqual(reverseReport.transactionsDeleted, 1)
        let remoteAccsAfterReverse = try await remoteStore.accounts(includeArchived: true)
        XCTAssertEqual(remoteAccsAfterReverse.count, 0, "원격 계좌에도 삭제가 전파되어야 함")
        let remoteTxsAfterReverse = try await remoteStore.transactions(TransactionQuery())
        XCTAssertEqual(remoteTxsAfterReverse.count, 0, "원격 거래에도 삭제가 전파되어야 함")
    }

    func testRemoteTombstonePropagatesToLocal() async throws {
        let localStore = try makeStore(name: "local_prop_test")
        let remoteStore = try makeStore(name: "remote_prop_test")

        // 1. 공통 데이터
        let card = MoneyCard(id: "card-shared-1", name: "공통카드", issuer: "현대", last4: "5555")
        try await localStore.save(card: card)
        try await remoteStore.save(card: card)

        let sub = MoneySubscription(id: "sub-shared-1", name: "공통구독", amountMinor: 5000, currency: "KRW", period: .monthly, status: .active)
        try await localStore.save(subscription: sub)
        try await remoteStore.save(subscription: sub)

        let budget = MoneyBudget(id: "budget-shared-1", category: "문화생활", amountMinor: 100_000, currency: "KRW")
        try await localStore.save(budget: budget)
        try await remoteStore.save(budget: budget)

        // 2. 원격에서 카드, 구독, 예산 삭제
        try await remoteStore.deleteCard(id: "card-shared-1")
        try await remoteStore.deleteSubscription(id: "sub-shared-1")
        try await remoteStore.deleteBudget(id: "budget-shared-1")

        let remoteCards = try await remoteStore.cards(includeArchived: true)
        XCTAssertEqual(remoteCards.count, 0)
        let remoteSubs = try await remoteStore.subscriptions(includeArchived: true)
        XCTAssertEqual(remoteSubs.count, 0)
        let remoteBudgets = try await remoteStore.budgets(month: nil)
        XCTAssertEqual(remoteBudgets.count, 0)

        // 3. 원격 -> 로컬 동기화 실행 (Delete Propagation 검증)
        let report = try await LedgerSyncEngine.merge(from: remoteStore, into: localStore, dryRun: false)

        XCTAssertEqual(report.cardsDeleted, 1)
        XCTAssertEqual(report.subscriptionsDeleted, 1)
        XCTAssertEqual(report.budgetsDeleted, 1)
        XCTAssertEqual(report.totalEntitiesDeleted, 3)

        // 로컬에서도 삭제되었는지 확인
        let localCards = try await localStore.cards(includeArchived: true)
        XCTAssertEqual(localCards.count, 0)
        let localSubs = try await localStore.subscriptions(includeArchived: true)
        XCTAssertEqual(localSubs.count, 0)
        let localBudgets = try await localStore.budgets(month: nil)
        XCTAssertEqual(localBudgets.count, 0)

        // 로컬 툼스톤에도 기록되었는지 확인
        let isCardTomb = try await localStore.isTombstoned(entityType: "card", entityID: "card-shared-1")
        XCTAssertTrue(isCardTomb)
        let isSubTomb = try await localStore.isTombstoned(entityType: "subscription", entityID: "sub-shared-1")
        XCTAssertTrue(isSubTomb)
        let isBudgetTomb = try await localStore.isTombstoned(entityType: "budget", entityID: "budget-shared-1")
        XCTAssertTrue(isBudgetTomb)

        // 4. 재동기화 멱등성 검증
        let idempotentReport = try await LedgerSyncEngine.merge(from: remoteStore, into: localStore, dryRun: false)
        XCTAssertEqual(idempotentReport.totalEntitiesAdded, 0)
        XCTAssertEqual(idempotentReport.totalEntitiesDeleted, 0)
    }

    func testTwoWayUpdateSyncMergesUpdatedEntitiesWithoutLoss() async throws {
        let localStore = try makeStore(name: "local_update_test")
        let remoteStore = try makeStore(name: "remote_update_test")

        let baseDate = Date(timeIntervalSince1970: 1000)
        let newerDate = Date(timeIntervalSince1970: 2000)

        // 1. 초기 공유 데이터 생성 (로컬/원격 동일)
        let accInitial = MoneyAccount(
            id: "acc-update-1",
            identity: MoneyAccount.Identity(name: "원래통장이름", bank: "국민", last4: "1111"),
            createdAt: baseDate,
            updatedAt: baseDate
        )
        try await localStore.save(account: accInitial)
        try await remoteStore.save(account: accInitial)

        let cardInitial = MoneyCard(
            id: "card-update-1",
            identity: MoneyCard.Identity(name: "원래카드이름", issuer: "국민", last4: "2222"),
            linkedAccountID: "acc-update-1",
            createdAt: baseDate,
            updatedAt: baseDate
        )
        try await localStore.save(card: cardInitial)
        try await remoteStore.save(card: cardInitial)

        let subInitial = MoneySubscription(
            id: "sub-update-1",
            name: "원래구독이름",
            amount: MoneySubscription.Amount(amountMinor: 9900, currency: "KRW"),
            createdAt: baseDate,
            updatedAt: baseDate
        )
        try await localStore.save(subscription: subInitial)
        try await remoteStore.save(subscription: subInitial)

        let budgetInitial = MoneyBudget(
            id: "budget-update-1",
            category: "식비",
            amountMinor: 500_000,
            currency: "KRW",
            createdAt: baseDate,
            updatedAt: baseDate
        )
        try await localStore.save(budget: budgetInitial)
        try await remoteStore.save(budget: budgetInitial)

        let templateInitial = RecurringTemplate(
            id: "tmpl-update-1",
            name: "원래고정비",
            dayOfMonth: 15,
            amountMinor: 100_000,
            currency: "KRW",
            createdAt: baseDate,
            updatedAt: baseDate
        )
        try await localStore.save(recurringTemplate: templateInitial)
        try await remoteStore.save(recurringTemplate: templateInitial)

        let bizInitial = BusinessProfile(
            id: "biz-update-1",
            identity: BusinessProfile.Identity(name: "원래상호", registrationNumber: "1234567890"),
            createdAt: baseDate,
            updatedAt: baseDate
        )
        try await localStore.save(business: bizInitial)
        try await remoteStore.save(business: bizInitial)

        // 2. 원격에서 필드 및 이름 수정 (최신 타임스탬프 부여)
        var accModified = accInitial
        accModified.name = "수정된통장이름"
        accModified.updatedAt = newerDate
        try await remoteStore.save(account: accModified)

        var cardModified = cardInitial
        cardModified.name = "수정된카드이름"
        cardModified.updatedAt = newerDate
        try await remoteStore.save(card: cardModified)

        var subModified = subInitial
        subModified.name = "수정된구독이름"
        subModified.amountMinor = 12900
        subModified.updatedAt = newerDate
        try await remoteStore.save(subscription: subModified)

        var budgetModified = budgetInitial
        budgetModified.amountMinor = 600_000
        budgetModified.updatedAt = newerDate
        try await remoteStore.save(budget: budgetModified)

        var templateModified = templateInitial
        templateModified.name = "수정된고정비"
        templateModified.amountMinor = 120_000
        templateModified.updatedAt = newerDate
        try await remoteStore.save(recurringTemplate: templateModified)

        var bizModified = bizInitial
        bizModified.name = "수정된상호"
        bizModified.updatedAt = newerDate
        try await remoteStore.save(business: bizModified)

        // 3. 원격 -> 로컬 동기화 실행
        let report = try await LedgerSyncEngine.merge(from: remoteStore, into: localStore, dryRun: false)

        // 기존의 !localAccountIDs.contains 버그가 해결되어 무시되지 않고 6개 모두 업데이트됨
        XCTAssertEqual(report.accountsAdded, 0)
        XCTAssertEqual(report.accountsUpdated, 1)
        XCTAssertEqual(report.cardsUpdated, 1)
        XCTAssertEqual(report.subscriptionsUpdated, 1)
        XCTAssertEqual(report.budgetsUpdated, 1)
        XCTAssertEqual(report.recurringTemplatesUpdated, 1)
        XCTAssertEqual(report.businessesUpdated, 1)
        XCTAssertEqual(report.totalEntitiesUpdated, 6)

        // 로컬 데이터에 원격 수정본이 완벽하게 반영되었는지 검증
        let localAccUpdated = try await localStore.account(idPrefix: "acc-update-1")
        XCTAssertEqual(localAccUpdated.name, "수정된통장이름")

        let localCardUpdated = try await localStore.card(idPrefix: "card-update-1")
        XCTAssertEqual(localCardUpdated.name, "수정된카드이름")

        let localSubUpdated = try await localStore.subscription(idPrefix: "sub-update-1")
        XCTAssertEqual(localSubUpdated.name, "수정된구독이름")
        XCTAssertEqual(localSubUpdated.amountMinor, 12900)

        let localBudgets = try await localStore.budgets(month: nil)
        XCTAssertEqual(localBudgets.first(where: { $0.id == "budget-update-1" })?.amountMinor, 600_000)

        let localTemplates = try await localStore.recurringTemplates(activeOnly: false)
        XCTAssertEqual(localTemplates.first(where: { $0.id == "tmpl-update-1" })?.name, "수정된고정비")
        XCTAssertEqual(localTemplates.first(where: { $0.id == "tmpl-update-1" })?.amountMinor, 120_000)

        let localBizUpdated = try await localStore.business(idPrefix: "biz-update-1")
        XCTAssertEqual(localBizUpdated.name, "수정된상호")

        // 4. 재동기화 멱등성 검증 (내용 일치 시 업데이트 0건)
        let idempotentReport2 = try await LedgerSyncEngine.merge(from: remoteStore, into: localStore, dryRun: false)
        XCTAssertEqual(idempotentReport2.totalEntitiesAdded, 0)
        XCTAssertEqual(idempotentReport2.totalEntitiesUpdated, 0)
    }

    func testSyncEngineThrowsWhenTombstonesFailsToPreventResurrection() async throws {
        let localStore = try makeStore(name: "local-tombstone-fail")
        let remoteStore = try makeStore(name: "remote-tombstone-fail")

        // 원격 DB의 tombstones 테이블을 삭제하여 tombstones 조회 에러 유발
        let remoteURL = tempDir.appendingPathComponent("remote-tombstone-fail.sqlite")
        var db: OpaquePointer?
        if sqlite3_open(remoteURL.path, &db) == SQLITE_OK {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, "DROP TABLE tombstones;", -1, &stmt, nil) == SQLITE_OK {
                _ = sqlite3_step(stmt)
                sqlite3_finalize(stmt)
            }
            sqlite3_close(db)
        }

        do {
            _ = try await LedgerSyncEngine.merge(from: remoteStore, into: localStore, dryRun: false)
            XCTFail("톰스톤 조회가 실패하면 데이터 부활 방지를 위해 즉시 에러를 throw해야 한다.")
        } catch {
            XCTAssertNotNil(error)
        }
    }
}
