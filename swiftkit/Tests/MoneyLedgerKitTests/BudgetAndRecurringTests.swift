import XCTest
import MoneyLedgerModels
@testable import MoneyLedgerStoreKit
@testable import MoneyLedgerReportKit

final class BudgetAndRecurringTests: XCTestCase {
    private var tempDir: URL = FileManager.default.temporaryDirectory

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("budget-recurring-tests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeStore() throws -> LedgerStore {
        try LedgerStore(url: tempDir.appendingPathComponent("ledger.sqlite"))
    }

    // MARK: - 예산(Budget) 저장 및 조회 테스트

    func testBudgetCRUDAndMonthlyOverride() async throws {
        let store = try makeStore()

        // 1. 기본 월별 예산 (month: nil)
        let defaultFoodBudget = MoneyBudget(
            category: "식비",
            month: nil,
            amountMinor: 500_000
        )
        try await store.save(budget: defaultFoodBudget)

        // 2. 2026-09 특화 예산 (명절 예산 증액)
        let sepFoodBudget = MoneyBudget(
            category: "식비",
            month: "2026-09",
            amountMinor: 700_000
        )
        try await store.save(budget: sepFoodBudget)

        // 3. 교통비 기본 예산
        let transportBudget = MoneyBudget(
            category: "교통",
            month: nil,
            amountMinor: 150_000
        )
        try await store.save(budget: transportBudget)

        // 전체 예산 목록 조회
        let allBudgets = try await store.budgets()
        XCTAssertEqual(allBudgets.count, 3)

        // 2026-09 유효 예산 조회: 식비는 700_000원으로 override 되어야 함
        let sepEffective = try await store.budgets(month: "2026-09")
        XCTAssertEqual(sepEffective.count, 2)
        let sepFood = sepEffective.first { $0.category == "식비" }
        XCTAssertEqual(sepFood?.amountMinor, 700_000)
        XCTAssertEqual(sepFood?.month, "2026-09")

        // 2026-10 유효 예산 조회: 식비는 기본 예산인 500_000원이어야 함
        let octEffective = try await store.budgets(month: "2026-10")
        let octFood = octEffective.first { $0.category == "식비" }
        XCTAssertEqual(octFood?.amountMinor, 500_000)
        XCTAssertNil(octFood?.month)

        // 예산 삭제
        try await store.deleteBudget(id: sepFoodBudget.id)
        let sepAfterDelete = try await store.budgets(month: "2026-09")
        let sepFoodFallback = sepAfterDelete.first { $0.category == "식비" }
        XCTAssertEqual(sepFoodFallback?.amountMinor, 500_000)
    }

    // MARK: - 예산 소진율 및 초과 감지 리포트 테스트

    func testBudgetProgressCalculationAndExceeded() {
        let budgets = [
            MoneyBudget(category: "식비", amountMinor: 500_000),
            MoneyBudget(category: "쇼핑", amountMinor: 200_000),
            MoneyBudget(category: "주거", amountMinor: 300_000),
        ]

        let transactions = [
            // 식비 지출 (정상 소진: 500,000 중 350,000 지출 -> 잔여 150,000, 비율 0.7)
            MoneyTransaction(
                date: "2026-09-05", amountMinor: -200_000,
                description: "마트", category: "식비", kind: .expense, contentHash: "h1"
            ),
            MoneyTransaction(
                date: "2026-09-12", amountMinor: -150_000,
                description: "외식", category: "식비", kind: .expense, contentHash: "h2"
            ),
            // 쇼핑 지출 (예산 초과: 200,000 중 250,000 지출 -> 잔여 -50,000, 비율 1.25, isExceeded = true)
            MoneyTransaction(
                date: "2026-09-15", amountMinor: -250_000,
                description: "의류", category: "쇼핑", kind: .expense, contentHash: "h3"
            ),
            // 주거: 지출 없음 -> 잔여 300,000, 비율 0.0, isExceeded = false
            // 타 월 거래 (2026-08) -> 제외되어야 함
            MoneyTransaction(
                date: "2026-08-30", amountMinor: -100_000,
                description: "8월 식비", category: "식비", kind: .expense, contentHash: "h4"
            ),
            // 이체 거래 -> 지출 집계에서 제외되어야 함
            MoneyTransaction(
                date: "2026-09-20", amountMinor: -100_000,
                description: "적금 이체", category: "주거", kind: .transfer, contentHash: "h5"
            ),
        ]

        let progressList = Reports.budgetProgress(budgets: budgets, transactions: transactions, month: "2026-09")
        XCTAssertEqual(progressList.count, 3)

        // 식비 검증
        let food = progressList.first { $0.category == "식비" }!
        XCTAssertEqual(food.budgetMinor, 500_000)
        XCTAssertEqual(food.spentMinor, 350_000)
        XCTAssertEqual(food.remainingMinor, 150_000)
        XCTAssertEqual(food.progressRatio, 0.7, accuracy: 0.001)
        XCTAssertFalse(food.isExceeded)

        // 쇼핑 검증 (초과)
        let shopping = progressList.first { $0.category == "쇼핑" }!
        XCTAssertEqual(shopping.budgetMinor, 200_000)
        XCTAssertEqual(shopping.spentMinor, 250_000)
        XCTAssertEqual(shopping.remainingMinor, -50_000)
        XCTAssertEqual(shopping.progressRatio, 1.25, accuracy: 0.001)
        XCTAssertTrue(shopping.isExceeded)

        // 주거 검증 (지출 0)
        let housing = progressList.first { $0.category == "주거" }!
        XCTAssertEqual(housing.budgetMinor, 300_000)
        XCTAssertEqual(housing.spentMinor, 0)
        XCTAssertEqual(housing.remainingMinor, 300_000)
        XCTAssertEqual(housing.progressRatio, 0.0)
        XCTAssertFalse(housing.isExceeded)
    }

    // MARK: - 고정비 템플릿 및 자동 생성 / 중복 방지 엔진 테스트

    func testRecurringTemplatesApplicationAndDeduplication() async throws {
        let store = try makeStore()

        // 계좌 준비
        let checkingAcct = MoneyAccount(name: "주거래통장", bank: "신한", currency: "KRW")
        let savingsAcct = MoneyAccount(name: "청년적금통장", bank: "국민", currency: "KRW")
        try await store.save(account: checkingAcct)
        try await store.save(account: savingsAcct)

        // 고정비 템플릿 등록
        // 1. 월세 (지출, 매월 25일, 50만원)
        let rentTemplate = RecurringTemplate(
            name: "월세",
            dayOfMonth: 25,
            amountMinor: 500_000,
            currency: "KRW",
            kind: .expense,
            category: "주거비",
            accountID: checkingAcct.id,
            memo: "원룸 월세"
        )
        try await store.save(recurringTemplate: rentTemplate)

        // 2. 적금 자동이체 (이체, 매월 10일, 30만원)
        let savingsTemplate = RecurringTemplate(
            name: "청년적금",
            dayOfMonth: 10,
            amountMinor: 300_000,
            currency: "KRW",
            kind: .transfer,
            category: "적금",
            accountID: checkingAcct.id,
            transferTargetAccountID: savingsAcct.id,
            memo: "희망적금"
        )
        try await store.save(recurringTemplate: savingsTemplate)

        // 3. 비활성 템플릿 (생성되지 않아야 함)
        let inactiveTemplate = RecurringTemplate(
            name: "헬스장",
            dayOfMonth: 1,
            amountMinor: 100_000,
            kind: .expense,
            isActive: false
        )
        try await store.save(recurringTemplate: inactiveTemplate)

        // 템플릿 조회 확인
        let activeTemplates = try await store.recurringTemplates(activeOnly: true)
        XCTAssertEqual(activeTemplates.count, 2)

        // --- 1회차 적용 (2026-09) ---
        let firstBatch = try await store.applyRecurringTemplates(month: "2026-09")
        // 월세 1건 + 적금 이체 쌍 2건 = 총 3건 생성
        XCTAssertEqual(firstBatch.count, 3)

        // 월세 거래 검증
        let rentTx = firstBatch.first { $0.description == "월세" }
        XCTAssertNotNil(rentTx)
        XCTAssertEqual(rentTx?.date, "2026-09-25")
        XCTAssertEqual(rentTx?.amountMinor, -500_000)
        XCTAssertEqual(rentTx?.kind, .expense)
        XCTAssertTrue(rentTx?.memo?.contains("[recurring:\(rentTemplate.id):2026-09]") == true)

        // 적금 이체 거래 검증 (출금/입금 쌍)
        let transferTxs = firstBatch.filter { $0.kind == .transfer }
        XCTAssertEqual(transferTxs.count, 2)
        let withdrawal = transferTxs.first { $0.amountMinor < 0 }
        let deposit = transferTxs.first { $0.amountMinor > 0 }
        XCTAssertEqual(withdrawal?.amountMinor, -300_000)
        XCTAssertEqual(withdrawal?.date, "2026-09-10")
        XCTAssertEqual(deposit?.amountMinor, 300_000)
        XCTAssertEqual(deposit?.date, "2026-09-10")

        // --- 2회차 재적용 (2026-09 멱등성 검증: 중복 생성 방지) ---
        let secondBatch = try await store.applyRecurringTemplates(month: "2026-09")
        XCTAssertTrue(secondBatch.isEmpty, "당월 이미 생성된 고정비는 중복 생성되지 않아야 합니다")

        // 총 거래 수는 여전히 3건이어야 함
        let totalCount = try await store.transactionCount()
        XCTAssertEqual(totalCount, 3)

        // --- 다음 달(2026-10) 적용 검증 ---
        let octBatch = try await store.applyRecurringTemplates(month: "2026-10")
        XCTAssertEqual(octBatch.count, 3, "새로운 달에는 고정비 거래가 새로 생성되어야 합니다")
        let octRentTx = octBatch.first { $0.description == "월세" }
        XCTAssertEqual(octRentTx?.date, "2026-10-25")
    }

    // MARK: - 월말 일수 클램핑 테스트 (예: 2월 28일/29일)

    func testRecurringDayClampingForShorterMonths() async throws {
        let store = try makeStore()

        let template31 = RecurringTemplate(
            name: "월말정산",
            dayOfMonth: 31,
            amountMinor: 50_000,
            kind: .expense
        )
        try await store.save(recurringTemplate: template31)

        // 2026년 2월 (28일까지 있음)
        let febTxs = try await store.applyRecurringTemplates(month: "2026-02")
        XCTAssertEqual(febTxs.count, 1)
        XCTAssertEqual(febTxs.first?.date, "2026-02-28", "2월 31일은 2월 28일로 클램핑되어야 합니다")

        // 2026년 4월 (30일까지 있음)
        let aprTxs = try await store.applyRecurringTemplates(month: "2026-04")
        XCTAssertEqual(aprTxs.count, 1)
        XCTAssertEqual(aprTxs.first?.date, "2026-04-30", "4월 31일은 4월 30일로 클램핑되어야 합니다")
    }
}
