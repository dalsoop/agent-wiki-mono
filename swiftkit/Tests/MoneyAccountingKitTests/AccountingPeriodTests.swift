import XCTest
import MoneyLedgerModels
@testable import MoneyAccountingKit

final class AccountingPeriodTests: XCTestCase {
    func testMonthAndQuarterAndHalf() throws {
        let february = try AccountingPeriod.month("2026-02")
        XCTAssertEqual(february.from, "2026-02-01")
        XCTAssertEqual(february.to, "2026-02-28")

        let leap = try AccountingPeriod.month("2028-02")
        XCTAssertEqual(leap.to, "2028-02-29")

        let q1 = try AccountingPeriod.quarter(year: 2026, quarter: 1)
        XCTAssertEqual(q1.from, "2026-01-01")
        XCTAssertEqual(q1.to, "2026-03-31")

        let secondHalf = AccountingPeriod.half(year: 2026, first: false)
        XCTAssertEqual(secondHalf.from, "2026-07-01")
        XCTAssertEqual(secondHalf.to, "2026-12-31")
        XCTAssertEqual(AccountingPeriod.year(2026).to, "2026-12-31")
    }

    func testInitNormalizesSeparators() throws {
        let period = try AccountingPeriod(from: "2026/5/6", to: "2026.06.30")
        XCTAssertEqual(period.from, "2026-05-06")
        XCTAssertEqual(period.to, "2026-06-30")
        XCTAssertTrue(period.contains("2026-06-01"))
    }

    func testContainsIsInclusive() throws {
        let period = try AccountingPeriod(from: "2026-05-06", to: "2026-06-30")
        XCTAssertTrue(period.contains("2026-05-06"))
        XCTAssertTrue(period.contains("2026-06-30"))
        XCTAssertFalse(period.contains("2026-05-05"))
        XCTAssertFalse(period.contains("2026-07-01"))
    }

    func testPreviousPeriod() throws {
        let august = try AccountingPeriod.month("2026-08")
        let july = try XCTUnwrap(august.previous())
        XCTAssertEqual(july.from, "2026-07-01")
        XCTAssertEqual(july.to, "2026-07-31")

        let previousYear = try XCTUnwrap(AccountingPeriod.year(2026).previous())
        XCTAssertEqual(previousYear.from, "2025-01-01")
        XCTAssertEqual(previousYear.to, "2025-12-31")
    }

    func testRejectsInvalidInput() {
        XCTAssertThrowsError(try AccountingPeriod(from: "2026-13-01", to: "2026-12-31"))
        XCTAssertThrowsError(try AccountingPeriod(from: "2026-12-31", to: "2026-01-01"))
        XCTAssertThrowsError(try AccountingPeriod.quarter(year: 2026, quarter: 5))
        XCTAssertThrowsError(try AccountingPeriod.month("2026/08"))
    }
}
