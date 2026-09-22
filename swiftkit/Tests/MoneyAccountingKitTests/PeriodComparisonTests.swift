import XCTest
import MoneyLedgerModels
@testable import MoneyAccountingKit

final class PeriodComparisonTests: XCTestCase {
    private func statement(month: String, sales: Int64, ai: Int64, fees: Int64 = 0, currency: String = "KRW") throws -> IncomeStatement {
        let period = try AccountingPeriod.month(month)
        let amounts = [
            AccountedAmount(accountCode: .sales, amountMinor: sales, currency: currency, date: period.from),
            AccountedAmount(accountCode: .aiApiUsage, amountMinor: ai, currency: currency, date: period.from),
            AccountedAmount(accountCode: .fees, amountMinor: fees, currency: currency, date: period.from),
        ]
        return IncomeStatementBuilder(amounts: amounts).build(period: period, currency: currency)
    }

    func testMetricsDeltaAndBasisPoints() throws {
        let current = try statement(month: "2026-08", sales: 1_200_000, ai: 300_000)
        let previous = try statement(month: "2026-07", sales: 1_000_000, ai: 400_000)
        let report = try PeriodComparison.compare(current: current, previous: previous)

        let revenue = try XCTUnwrap(report.metrics.first { $0.key == .revenue })
        XCTAssertEqual(revenue.delta.deltaMinor, 200_000)
        XCTAssertEqual(revenue.delta.changeBasisPoints, 2_000)  // +20.00%

        let cost = try XCTUnwrap(report.metrics.first { $0.key == .costOfSales })
        XCTAssertEqual(cost.delta.deltaMinor, -100_000)
        XCTAssertEqual(cost.delta.changeBasisPoints, -2_500)  // -25.00%

        let gross = try XCTUnwrap(report.metrics.first { $0.key == .grossProfit })
        XCTAssertEqual(gross.delta.currentMinor, 900_000)
        XCTAssertEqual(gross.delta.previousMinor, 600_000)
        XCTAssertEqual(gross.delta.changeBasisPoints, 5_000)
        XCTAssertEqual(report.metrics.count, PeriodComparison.MetricKey.allCases.count)
    }

    func testZeroPreviousHasNoRate() {
        XCTAssertNil(PeriodComparison.basisPoints(delta: 500, previous: 0))
        XCTAssertEqual(PeriodComparison.basisPoints(delta: 0, previous: 100), 0)
        XCTAssertEqual(PeriodComparison.basisPoints(delta: 1, previous: 3), 3_333)  // 33.33…% → 0 방향 절사
        XCTAssertEqual(PeriodComparison.basisPoints(delta: -1, previous: 3), -3_333)
    }

    func testNegativePreviousUsesMagnitude() {
        // 적자 -100,000 → -50,000: 손실이 절반으로 줄었으니 +50.00%.
        XCTAssertEqual(PeriodComparison.basisPoints(delta: 50_000, previous: -100_000), 5_000)
    }

    func testOverflowYieldsNil() {
        XCTAssertNil(PeriodComparison.basisPoints(delta: Int64.max, previous: 1))
    }

    func testLinesAreUnionInDisplayOrder() throws {
        let current = try statement(month: "2026-08", sales: 1_000, ai: 0, fees: 300)
        let previous = try statement(month: "2026-07", sales: 800, ai: 200)
        let report = try PeriodComparison.compare(current: current, previous: previous)
        XCTAssertEqual(report.lines.map(\.accountCode), [.sales, .aiApiUsage, .fees])
        let fees = try XCTUnwrap(report.lines.first { $0.accountCode == .fees })
        XCTAssertEqual(fees.delta.previousMinor, 0)
        XCTAssertNil(fees.delta.changeBasisPoints)
        let ai = try XCTUnwrap(report.lines.first { $0.accountCode == .aiApiUsage })
        XCTAssertEqual(ai.delta.changeBasisPoints, -10_000)
    }

    func testCurrencyMismatchThrows() throws {
        let krw = try statement(month: "2026-08", sales: 1_000, ai: 0)
        let usd = try statement(month: "2026-07", sales: 1_000, ai: 0, currency: "USD")
        XCTAssertThrowsError(try PeriodComparison.compare(current: krw, previous: usd)) { error in
            XCTAssertEqual(error as? PeriodComparisonError, .currencyMismatch(current: "KRW", previous: "USD"))
        }
    }
}
