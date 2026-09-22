import XCTest
import MoneyLedgerModels
@testable import MoneyLedgerStoreKit
@testable import MoneyLedgerReportKit

final class AccountingIntegrityTests: XCTestCase {
    private var tempDir: URL?

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("accounting-integrity-tests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
    }

    private func makeStore() throws -> LedgerStore {
        guard let tempDir else { throw XCTSkip("no tempDir") }
        return try LedgerStore(url: tempDir.appendingPathComponent("ledger.sqlite"))
    }

    // MARK: - 시나리오 1: 계좌 기초잔액 및 잔액 계산 테스트
    /// 기초잔액 1,000,000원에서 지출 200,000원, 수입 500,000원 발생 시 잔액 1,300,000원 정확 산출 검증.
    func testAccountOpeningBalanceAndCalculation() async throws {
        let store = try makeStore()

        // 1. 기초잔액 1,000,000원 계좌 생성
        let account = MoneyAccount(
            name: "주거래통장",
            bank: "신한",
            last4: "1234",
            currency: "KRW",
            accountType: .checking,
            initialBalanceMinor: 1_000_000
        )
        try await store.save(account: account)

        // openingBalanceMinor 와 initialBalanceMinor 가 일치하는지 확인
        XCTAssertEqual(account.initialBalanceMinor, 1_000_000)
        XCTAssertEqual(account.openingBalanceMinor, 1_000_000)

        // 2. 지출 200,000원 발생
        let expenseHash = ContentHash.transactionHash(
            date: "2026-09-01",
            time: "10:00:00",
            amountMinor: -200_000,
            currency: "KRW",
            instrumentID: account.id,
            description: "사무용품 구입",
            balanceAfterMinor: nil
        )
        let expenseTx = MoneyTransaction(
            date: "2026-09-01",
            amountMinor: -200_000,
            currency: "KRW",
            accountID: account.id,
            description: "사무용품 구입",
            category: "사무비",
            kind: .expense,
            contentHash: expenseHash
        )
        _ = try await store.insert(transaction: expenseTx)

        // 3. 수입 500,000원 발생
        let incomeHash = ContentHash.transactionHash(
            date: "2026-09-02",
            time: "14:00:00",
            amountMinor: 500_000,
            currency: "KRW",
            instrumentID: account.id,
            description: "외주 정산 입금",
            balanceAfterMinor: nil
        )
        let incomeTx = MoneyTransaction(
            date: "2026-09-02",
            amountMinor: 500_000,
            currency: "KRW",
            accountID: account.id,
            description: "외주 정산 입금",
            category: "매출",
            kind: .income,
            contentHash: incomeHash
        )
        _ = try await store.insert(transaction: incomeTx)

        // 4. Reports 순수 함수 잔액 계산 검증: 1,000,000 - 200,000 + 500,000 = 1,300,000원
        let calculatedReportBalance = Reports.accountBalance(
            account: account,
            transactions: [expenseTx, incomeTx]
        )
        XCTAssertEqual(calculatedReportBalance, 1_300_000)

        // 5. LedgerStore DB 잔액 조회 검증
        let storeBalance = try await store.balance(forAccountID: account.id)
        XCTAssertEqual(storeBalance, 1_300_000)
    }

    // MARK: - 시나리오 2: 계좌 간 이체(Transfer) 현금흐름 왜곡 차단 테스트
    /// A계좌에서 B계좌로 500,000원 이체 시, 두 계좌의 잔액은 각각 -500,000원, +500,000원 변동되지만
    /// `monthlyFlow` 및 `categoryTotals`의 월간 수입/지출 합산에는 전혀 잡히지 않음을 검증.
    func testInterAccountTransferPreventsCashFlowDistortion() async throws {
        let store = try makeStore()

        let accountA = MoneyAccount(name: "A계좌", bank: "국민", currency: "KRW", openingBalanceMinor: 1_000_000)
        let accountB = MoneyAccount(name: "B계좌", bank: "우리", currency: "KRW", openingBalanceMinor: 200_000)
        try await store.save(account: accountA)
        try await store.save(account: accountB)

        // 500,000원 이체 쌍 생성 (A -> B)
        let (withdrawal, deposit) = try await store.createTransfer(
            fromAccountID: accountA.id,
            toAccountID: accountB.id,
            amountMinor: 500_000,
            currency: "KRW",
            date: "2026-09-10",
            description: "예비비 이체"
        )

        XCTAssertEqual(withdrawal.amountMinor, -500_000)
        XCTAssertEqual(withdrawal.kind, .transfer)
        XCTAssertEqual(deposit.amountMinor, 500_000)
        XCTAssertEqual(deposit.kind, .transfer)

        // 1. 잔액 변동 검증: A계좌는 1,000,000 -> 500,000 (-500,000원 변동), B계좌는 200,000 -> 700,000 (+500,000원 변동)
        let balanceA = try await store.balance(forAccountID: accountA.id)
        let balanceB = try await store.balance(forAccountID: accountB.id)
        XCTAssertEqual(balanceA, 500_000)
        XCTAssertEqual(balanceB, 700_000)

        // 2. monthlyFlow 에서 이체 거래는 완전히 제외되는지 검증
        let transferTxs = [withdrawal, deposit]
        let flows = Reports.monthlyFlow(transactions: transferTxs)
        XCTAssertTrue(flows.isEmpty, "이체 거래만 있을 경우 월간 현금흐름 버킷은 비어있어야 함 (현금흐름 왜곡 차단)")

        // 3. 일반 지출(커피 4,500원)과 혼합되었을 때 이체가 수입/지출 합산에 잡히지 않는지 검증
        let coffeeTx = MoneyTransaction(
            date: "2026-09-10",
            amountMinor: -4500,
            currency: "KRW",
            accountID: accountA.id,
            description: "커피",
            category: "식비",
            kind: .expense,
            contentHash: "hash-coffee"
        )
        let mixedFlows = Reports.monthlyFlow(transactions: [withdrawal, deposit, coffeeTx])
        XCTAssertEqual(mixedFlows.count, 1)
        guard let krwFlow = mixedFlows.first else {
            XCTFail("mixedFlows.first is nil")
            return
        }
        XCTAssertEqual(krwFlow.inflowMinor, 0, "이체 입금 500,000원이 수입으로 잡히지 않아야 함")
        XCTAssertEqual(krwFlow.outflowMinor, -4500, "이체 출금 500,000원이 지출로 잡히지 않고 실제 커피 지출만 잡혀야 함")
        XCTAssertEqual(krwFlow.transactionCount, 1)

        // 4. categoryTotals 에서도 이체가 잡히지 않는지 검증
        let categoryTotals = Reports.categoryTotals(transactions: [withdrawal, deposit, coffeeTx])
        XCTAssertEqual(categoryTotals.count, 1)
        XCTAssertEqual(categoryTotals.first?.category, "식비")
        XCTAssertEqual(categoryTotals.first?.totalMinor, -4500)
    }

    // MARK: - 시나리오 3: 카드대금 납부(Card Settlement) 및 카드 부채 상환 테스트
    /// 카드 지출 100,000원(부채 발생) -> 계좌에서 카드대금 100,000원 납부 -> 카드 미결제 잔액이 0으로 상환되고 지출이 이중 계상되지 않음을 검증.
    func testCardSettlementAndDebtRepaymentWithoutDoubleCounting() async throws {
        let store = try makeStore()

        let bankAccount = MoneyAccount(name: "결제계좌", bank: "하나", currency: "KRW", openingBalanceMinor: 1_000_000)
        let card = MoneyCard(name: "현대카드", issuer: "현대", last4: "9876", linkedAccountID: bankAccount.id)
        try await store.save(account: bankAccount)
        try await store.save(card: card)

        // 1. 카드 지출 100,000원 발생 (카드 부채 발생)
        let cardExpenseHash = ContentHash.transactionHash(
            date: "2026-08-15",
            time: nil,
            amountMinor: -100_000,
            currency: "KRW",
            instrumentID: card.id,
            description: "레스토랑 회식",
            balanceAfterMinor: nil
        )
        var cardExpense = MoneyTransaction(
            date: "2026-08-15",
            amountMinor: -100_000,
            currency: "KRW",
            description: "레스토랑 회식",
            category: "식비",
            kind: .expense,
            contentHash: cardExpenseHash
        )
        cardExpense.cardID = card.id
        _ = try await store.insert(transaction: cardExpense)

        // 납부 전 카드 미결제 잔액 검증: 100,000원
        let preSettlementBalance = try await store.cardBalance(forCardID: card.id)
        XCTAssertEqual(preSettlementBalance, 100_000)

        // 순자산 리포트 상에서도 카드 부채 100,000원 반영 확인
        let preReports = Reports.netWorth(
            accounts: [bankAccount],
            cards: [card],
            transactions: [cardExpense]
        )
        XCTAssertEqual(preReports.first?.totalLiabilitiesMinor, 100_000)

        // 2. 계좌에서 카드대금 100,000원 결제/납부
        let (accountWithdrawal, cardPayment) = try await store.settleCard(
            fromAccountID: bankAccount.id,
            cardID: card.id,
            amountMinor: 100_000,
            currency: "KRW",
            date: "2026-09-05",
            description: "현대카드 8월 이용대금"
        )
        XCTAssertEqual(accountWithdrawal.kind, .settlement)
        XCTAssertEqual(cardPayment.kind, .settlement)

        // 3. 카드 미결제 잔액이 0으로 상환되었는지 검증
        let postSettlementBalance = try await store.cardBalance(forCardID: card.id)
        XCTAssertEqual(postSettlementBalance, 0, "카드대금 납부 후 카드 미결제 잔액은 0이어야 함")

        // 은행 계좌 잔액은 1,000,000원에서 100,000원 출금되어 900,000원이어야 함
        let bankBalance = try await store.balance(forAccountID: bankAccount.id)
        XCTAssertEqual(bankBalance, 900_000)

        // 4. 지출이 이중 계상되지 않음을 검증 (monthlyFlow & categoryTotals)
        let allTransactions = [cardExpense, accountWithdrawal, cardPayment]
        let flows = Reports.monthlyFlow(transactions: allTransactions)
        XCTAssertEqual(flows.count, 1)
        guard let krwFlow = flows.first else {
            XCTFail("flows.first is nil")
            return
        }
        XCTAssertEqual(
            krwFlow.outflowMinor,
            -100_000,
            "카드대금 납부액은 지출에 이중 합산되지 않고 최초 카드 지출 100,000원만 기록되어야 함"
        )

        let categories = Reports.categoryTotals(transactions: allTransactions)
        XCTAssertEqual(categories.count, 1)
        XCTAssertEqual(categories.first?.category, "식비")
        XCTAssertEqual(categories.first?.totalMinor, -100_000)

        // 순자산 리포트에서도 카드 부채가 0으로 상환되고 순자산이 900,000원(계좌잔액 900,000원)임을 검증
        let postReports = Reports.netWorth(
            accounts: [bankAccount],
            cards: [card],
            transactions: allTransactions
        )
        XCTAssertEqual(postReports.first?.totalLiabilitiesMinor, 0)
        XCTAssertEqual(postReports.first?.netWorthMinor, 900_000)
    }

    // MARK: - 시나리오 4: 순자산(Net Worth) 및 자산 배분 비중(Asset Allocation) 산출 테스트
    /// 예적금 1천만, 투자 2천만, 부동산 7천만, 대출 3천만 보유 시 ->
    /// 총자산 1억, 총부채 3천만, 순자산 7천만 및 자산군별 비율이 정확히 계산되는지 검증.
    func testNetWorthAndAssetAllocationCalculation() {
        let savingsAccount = MoneyAccount(
            name: "정기적금",
            bank: "카카오뱅크",
            currency: "KRW",
            accountType: .savings,
            openingBalanceMinor: 10_000_000 // 1천만원
        )
        let investmentAccount = MoneyAccount(
            name: "국내주식",
            bank: "키움증권",
            currency: "KRW",
            accountType: .investment,
            openingBalanceMinor: 20_000_000 // 2천만원
        )
        let realEstateAccount = MoneyAccount(
            name: "자가 아파트",
            bank: "부동산자산",
            currency: "KRW",
            accountType: .realEstate,
            openingBalanceMinor: 70_000_000 // 7천만원
        )
        let loanAccount = MoneyAccount(
            name: "주택담보대출",
            bank: "국민은행",
            currency: "KRW",
            accountType: .loan,
            openingBalanceMinor: 30_000_000 // 3천만원
        )

        let accounts = [savingsAccount, investmentAccount, realEstateAccount, loanAccount]
        let reports = Reports.netWorth(accounts: accounts, cards: [], transactions: [])

        XCTAssertEqual(reports.count, 1)
        guard let report = reports.first else {
            XCTFail("reports.first is nil")
            return
        }
        XCTAssertEqual(report.currency, "KRW")

        // 총자산 = 예적금 1천만 + 투자 2천만 + 부동산 7천만 = 100,000,000원 (1억)
        XCTAssertEqual(report.totalAssetsMinor, 100_000_000)

        // 총부채 = 대출 30,000,000원 (3천만)
        XCTAssertEqual(report.totalLiabilitiesMinor, 30_000_000)

        // 순자산 = 총자산(1억) - 총부채(3천만) = 70,000,000원 (7천만)
        XCTAssertEqual(report.netWorthMinor, 70_000_000)

        // 자산군별 비율 검증
        // 1) 부동산: 70,000,000 / 100,000,000 = 70.0%
        let realEstate = report.assetGroups.first { $0.type == MoneyAccountType.realEstate.rawValue }
        XCTAssertNotNil(realEstate)
        XCTAssertEqual(realEstate?.amountMinor, 70_000_000)
        if let realEstate {
            XCTAssertEqual(realEstate.percentage, 70.0, accuracy: 0.001)
        }

        // 2) 투자: 20,000,000 / 100,000,000 = 20.0%
        let investment = report.assetGroups.first { $0.type == MoneyAccountType.investment.rawValue }
        XCTAssertNotNil(investment)
        XCTAssertEqual(investment?.amountMinor, 20_000_000)
        if let investment {
            XCTAssertEqual(investment.percentage, 20.0, accuracy: 0.001)
        }

        // 3) 예적금: 10,000,000 / 100,000,000 = 10.0%
        let savings = report.assetGroups.first { $0.type == MoneyAccountType.savings.rawValue }
        XCTAssertNotNil(savings)
        XCTAssertEqual(savings?.amountMinor, 10_000_000)
        if let savings {
            XCTAssertEqual(savings.percentage, 10.0, accuracy: 0.001)
        }

        // 부채 비중 검증: 대출 3천만 (100.0%)
        let loan = report.liabilityGroups.first { $0.type == MoneyAccountType.loan.rawValue }
        XCTAssertNotNil(loan)
        XCTAssertEqual(loan?.amountMinor, 30_000_000)
        if let loan {
            XCTAssertEqual(loan.percentage, 100.0, accuracy: 0.001)
        }
    }

    // MARK: - 시나리오 5: 동일 거래 ContentHash 충돌 방지 테스트
    /// 동일 날짜, 동일 금액, 동일 가맹점(예: 같은 날 커피 4,500원 2회) 수동 입력 시
    /// 두 거래가 모두 SQLite에 정상 보존되는지 검증.
    func testIdenticalTransactionContentHashCollisionPrevention() async throws {
        let store = try makeStore()
        let account = MoneyAccount(name: "체크카드계좌", bank: "토스", currency: "KRW")
        try await store.save(account: account)

        let date = "2026-09-11"
        let amountMinor: Int64 = -4500
        let description = "블루보틀 강남점"

        // 1. 첫 번째 커피 구매 (수동 입력): nextOccurrence() 로 occurrence 1 획득
        let occ1 = try await store.nextOccurrence(
            date: date,
            amountMinor: amountMinor,
            currency: "KRW",
            instrumentID: account.id,
            description: description
        )
        XCTAssertEqual(occ1, 1)

        let hash1 = ContentHash.transactionHash(
            date: date,
            time: nil,
            amountMinor: amountMinor,
            currency: "KRW",
            instrumentID: account.id,
            description: description,
            balanceAfterMinor: nil,
            occurrence: occ1
        )
        let tx1 = MoneyTransaction(
            date: date,
            amountMinor: amountMinor,
            currency: "KRW",
            accountID: account.id,
            description: description,
            category: "식비",
            kind: .expense,
            contentHash: hash1
        )
        let outcome1 = try await store.insert(transaction: tx1)
        XCTAssertFalse(outcome1.duplicate, "첫 번째 거래는 중복이 아니어야 함")

        // 2. 같은 날 동일 가맹점에서 두 번째 커피 구매: nextOccurrence() 가 이미 저장된 occurrence 1을 인식하고 2 반환
        let occ2 = try await store.nextOccurrence(
            date: date,
            amountMinor: amountMinor,
            currency: "KRW",
            instrumentID: account.id,
            description: description
        )
        XCTAssertEqual(occ2, 2, "동일 조건 거래가 이미 DB에 존재하므로 occurrence는 2여야 함")
        XCTAssertNotEqual(occ1, occ2)

        let hash2 = ContentHash.transactionHash(
            date: date,
            time: nil,
            amountMinor: amountMinor,
            currency: "KRW",
            instrumentID: account.id,
            description: description,
            balanceAfterMinor: nil,
            occurrence: occ2
        )
        XCTAssertNotEqual(hash1, hash2, "occurrence 가 다르므로 ContentHash 는 충돌하지 않아야 함")

        let tx2 = MoneyTransaction(
            date: date,
            amountMinor: amountMinor,
            currency: "KRW",
            accountID: account.id,
            description: description,
            category: "식비",
            kind: .expense,
            contentHash: hash2
        )
        let outcome2 = try await store.insert(transaction: tx2)
        XCTAssertFalse(outcome2.duplicate, "occurrence 가 달라 hash 가 다르므로 두 번째 거래도 중복 처리되지 않아야 함")

        // 3. SQLite 원장에 2건의 거래가 온전히 보존되어 있는지 최종 검증
        let totalCount = try await store.transactionCount()
        XCTAssertEqual(totalCount, 2, "두 거래 모두 SQLite 에 정상 보존되어야 함")

        let listedTxs = try await store.transactions()
        XCTAssertEqual(listedTxs.count, 2)
        XCTAssertEqual(Set(listedTxs.map(\.contentHash)).count, 2, "두 거래의 해시는 서로 달라야 함")
        XCTAssertEqual(Set(listedTxs.map(\.id)).count, 2, "두 거래의 ID는 서로 달라야 함")

        // 계좌 잔액도 -9,000원(4,500원 2회) 정확 반영 검증
        let finalBalance = try await store.balance(forAccountID: account.id)
        XCTAssertEqual(finalBalance, -9000)
    }
}
