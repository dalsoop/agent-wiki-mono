import XCTest
import MoneyLedgerModels
@testable import MoneyAccountingKit

final class IncomeStatementBuilderTests: XCTestCase {
    private func amount(_ code: AccountCode, _ minor: Int64, currency: String = "KRW", date: String = "2026-08-03") -> AccountedAmount {
        AccountedAmount(accountCode: code, amountMinor: minor, currency: currency, date: date)
    }

    private var sample: [AccountedAmount] {
        [
            amount(.sales, 1_100_000),
            amount(.sales, -100_000, date: "2026-08-20"),  // 환불 = 음수 매출
            amount(.aiApiUsage, 200_000),
            amount(.hostingAndCloud, 50_000),
            amount(.fees, 30_000),
            amount(.rent, 100_000),
            amount(.interestIncome, 1_000),
            amount(.interestExpense, 5_000),
            amount(.ownerDrawing, 300_000),
            amount(.sales, 999_999, date: "2026-09-01"),  // 기간 밖
            amount(.aiApiUsage, 1599, currency: "USD"),  // 다른 통화
        ]
    }

    func testBuildsSingleCurrencyStatementWithDerivedTotals() throws {
        let statement = IncomeStatementBuilder(amounts: sample).build(period: try .month("2026-08"))
        XCTAssertEqual(statement.currency, "KRW")
        XCTAssertEqual(statement.revenueMinor, 1_000_000)
        XCTAssertEqual(statement.costOfSalesMinor, 250_000)
        XCTAssertEqual(statement.grossProfitMinor, 750_000)
        XCTAssertEqual(statement.sellingAndAdministrativeMinor, 130_000)
        XCTAssertEqual(statement.operatingIncomeMinor, 620_000)
        XCTAssertEqual(statement.nonOperatingIncomeMinor, 1_000)
        XCTAssertEqual(statement.nonOperatingExpenseMinor, 5_000)
        XCTAssertEqual(statement.incomeBeforeTaxMinor, 616_000)
        XCTAssertEqual(statement.entryCount, 9)
    }

    func testCapitalTransactionsExcludedFromIncomeButReported() throws {
        let statement = IncomeStatementBuilder(amounts: sample).build(period: try .month("2026-08"))
        XCTAssertFalse(statement.lines.contains { $0.accountCode == .ownerDrawing })
        XCTAssertEqual(statement.capitalTransactionLines.map(\.accountCode), [.ownerDrawing])
        XCTAssertEqual(statement.amount(of: .ownerDrawing), 300_000)
        XCTAssertEqual(statement.lines(in: .capitalTransaction).count, 1)
    }

    func testLinesAggregateAndFollowDisplayOrder() throws {
        let statement = IncomeStatementBuilder(amounts: sample).build(period: try .month("2026-08"))
        let sales = try XCTUnwrap(statement.lines.first)
        XCTAssertEqual(sales.accountCode, .sales)
        XCTAssertEqual(sales.amountMinor, 1_000_000)
        XCTAssertEqual(sales.entryCount, 2)
        XCTAssertEqual(statement.lines.map(\.accountCode), [.sales, .aiApiUsage, .hostingAndCloud, .rent, .fees, .interestIncome, .interestExpense])
    }

    func testBuildAllNeverMergesCurrencies() throws {
        let statements = IncomeStatementBuilder(amounts: sample).buildAll(period: try .month("2026-08"))
        XCTAssertEqual(statements.map(\.currency), ["KRW", "USD"])
        let usd = try XCTUnwrap(statements.last)
        XCTAssertEqual(usd.costOfSalesMinor, 1599)
        XCTAssertEqual(usd.revenueMinor, 0)
    }

    func testEmptyPeriodProducesZeroStatement() throws {
        let statement = IncomeStatementBuilder(amounts: sample).build(period: try .month("2025-01"))
        XCTAssertEqual(statement.incomeBeforeTaxMinor, 0)
        XCTAssertTrue(statement.lines.isEmpty)
        XCTAssertEqual(statement.entryCount, 0)
    }

    func testStatementRoundTripsThroughJSONWithDerivedFields() throws {
        let statement = IncomeStatementBuilder(amounts: sample).build(period: try .month("2026-08"))
        let data = try JSONEncoder().encode(statement)
        let decoded = try JSONDecoder().decode(IncomeStatement.self, from: data)
        XCTAssertEqual(decoded, statement)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("incomeBeforeTaxMinor"))
    }
}
