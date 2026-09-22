import XCTest
import MoneyLedgerModels
@testable import KoreanTaxRulesKit

final class KoreanTaxCalendarTests: XCTestCase {
    private func calendar() throws -> KoreanTaxCalendar {
        try KoreanTaxCalendar.loadBundled()
    }

    private func find(_ kind: TaxDeadlineKind, in deadlines: [TaxDeadline]) throws -> TaxDeadline {
        try XCTUnwrap(deadlines.first { $0.kind == kind }, kind.rawValue)
    }

    /// 라노드: 2026-05-06 개업 개인 일반과세자. 1기 확정 기한 7/25 가 토요일이라 7/27.
    func testRanodeFirstVATPeriodIsTruncatedAndRolledToMonday() throws {
        let deadlines = try calendar().deadlines(year: 2026, openedOn: "2026-05-06")
        let first = try find(.vatFirstHalfFinal, in: deadlines)
        XCTAssertEqual(first.periodFrom, "2026-05-06")
        XCTAssertEqual(first.periodTo, "2026-06-30")
        XCTAssertEqual(first.statutoryDate, "2026-07-25")
        XCTAssertEqual(first.dueDate, "2026-07-27")
        XCTAssertTrue(first.rolledOver)
        XCTAssertEqual(first.confidence, .confirmed)
        XCTAssertEqual(first.taxYear, 2026)
        XCTAssertTrue(first.note.contains("국세기본법 제5조"))
    }

    func testRanode2026FullSchedule() throws {
        let deadlines = try calendar().deadlines(year: 2026, openedOn: "2026-05-06")
        XCTAssertEqual(
            deadlines.map(\.kind),
            [.vatFirstHalfFinal, .vatSecondHalfPreliminaryNotice, .vatSecondHalfFinal, .comprehensiveIncomeTax]
        )
        XCTAssertNil(deadlines.first { $0.kind == .vatFirstHalfPreliminaryNotice }, "개업 전 예정고지는 없다")

        let notice = try find(.vatSecondHalfPreliminaryNotice, in: deadlines)
        XCTAssertEqual(notice.statutoryDate, "2026-10-25")
        XCTAssertEqual(notice.dueDate, "2026-10-26")  // 일요일 → 월요일
        XCTAssertEqual(notice.confidence, .needsReview)
        XCTAssertTrue(notice.note.contains("₩500,000"))

        let second = try find(.vatSecondHalfFinal, in: deadlines)
        XCTAssertEqual(second.periodFrom, "2026-07-01")
        XCTAssertEqual(second.dueDate, "2027-01-25")
        XCTAssertFalse(second.rolledOver)

        let income = try find(.comprehensiveIncomeTax, in: deadlines)
        XCTAssertEqual(income.periodFrom, "2026-05-06")
        XCTAssertEqual(income.periodTo, "2026-12-31")
        XCTAssertEqual(income.dueDate, "2027-05-31")
        XCTAssertFalse(income.rolledOver)
    }

    func testSincereReportingMovesIncomeTaxToJuneEnd() throws {
        let taxpayer = Taxpayer(isSincereReportingSubject: true)
        let deadlines = try calendar().deadlines(year: 2026, taxpayer: taxpayer, openedOn: "2026-05-06")
        let income = try find(.sincereReportingIncomeTax, in: deadlines)
        XCTAssertEqual(income.dueDate, "2027-06-30")
        XCTAssertNil(deadlines.first { $0.kind == .comprehensiveIncomeTax })
    }

    func testMonthlyWithholdingStartsAtOpeningMonth() throws {
        let taxpayer = Taxpayer(withholding: .monthly)
        let deadlines = try calendar().deadlines(year: 2026, taxpayer: taxpayer, openedOn: "2026-05-06")
        let withholding = deadlines.filter { $0.kind == .withholdingTaxMonthly }
        XCTAssertEqual(withholding.count, 8)  // 5월~12월
        XCTAssertEqual(withholding.first?.periodFrom, "2026-05-06")
        XCTAssertEqual(withholding.first?.dueDate, "2026-06-10")
        let december = try XCTUnwrap(withholding.last)
        XCTAssertEqual(december.statutoryDate, "2027-01-10")
        XCTAssertEqual(december.dueDate, "2027-01-11")  // 일요일 → 월요일
    }

    func testHalfYearlyWithholding() throws {
        let taxpayer = Taxpayer(withholding: .halfYearly)
        let deadlines = try calendar().deadlines(year: 2026, taxpayer: taxpayer)
        let halves = deadlines.filter { $0.kind == .withholdingTaxHalfYearly }
        XCTAssertEqual(halves.map(\.dueDate), ["2026-07-10", "2027-01-11"])
    }

    func testFullYearBusinessHasBothPreliminaryNotices() throws {
        let deadlines = try calendar().deadlines(year: 2027)
        XCTAssertEqual(
            deadlines.map(\.kind),
            [.vatFirstHalfPreliminaryNotice, .vatFirstHalfFinal, .vatSecondHalfPreliminaryNotice,
             .vatSecondHalfFinal, .comprehensiveIncomeTax]
        )
        let firstNotice = try find(.vatFirstHalfPreliminaryNotice, in: deadlines)
        XCTAssertEqual(firstNotice.statutoryDate, "2027-04-25")
        XCTAssertEqual(firstNotice.dueDate, "2027-04-26")  // 일요일
        XCTAssertEqual(try find(.vatFirstHalfFinal, in: deadlines).dueDate, "2027-07-26")  // 7/25 일요일
        XCTAssertEqual(try find(.vatSecondHalfFinal, in: deadlines).dueDate, "2028-01-25")
        XCTAssertEqual(try find(.comprehensiveIncomeTax, in: deadlines).periodFrom, "2027-01-01")
    }

    func testOpeningInSecondHalfSkipsFirstPeriodAndNotice() throws {
        let deadlines = try calendar().deadlines(year: 2026, openedOn: "2026-08-01")
        XCTAssertEqual(deadlines.map(\.kind), [.vatSecondHalfFinal, .comprehensiveIncomeTax])
        XCTAssertEqual(try find(.vatSecondHalfFinal, in: deadlines).periodFrom, "2026-08-01")
    }

    func testOpeningAfterTaxYearYieldsNothing() throws {
        XCTAssertTrue(try calendar().deadlines(year: 2026, openedOn: "2027-01-01").isEmpty)
    }

    func testInvalidOpeningDateThrows() throws {
        XCTAssertThrowsError(try calendar().deadlines(year: 2026, openedOn: "개업일 미정")) { error in
            XCTAssertEqual(error as? KoreanTaxCalendarError, .invalidOpeningDate("개업일 미정"))
        }
        XCTAssertThrowsError(try calendar().deadlines(year: 2026, openedOn: "2026-13-01"))
    }

    /// 구분자가 다른 표기는 정규화돼 같은 결과 — 사전순 비교가 구분자에 흔들리면 안 된다.
    func testOpeningDateIsNormalizedBeforeComparison() throws {
        let slashed = try calendar().deadlines(year: 2026, openedOn: "2026/05/06")
        let dotted = try calendar().deadlines(year: 2026, openedOn: "2026.5.6")
        let canonical = try calendar().deadlines(year: 2026, openedOn: "2026-05-06")
        XCTAssertEqual(slashed, canonical)
        XCTAssertEqual(dotted, canonical)
        XCTAssertEqual(try find(.vatFirstHalfFinal, in: slashed).periodFrom, "2026-05-06")
    }

    func testYearWithoutHolidayTableIsFlaggedNeedsReview() throws {
        let deadlines = try calendar().deadlines(year: 2030)
        XCTAssertFalse(deadlines.isEmpty)
        for deadline in deadlines {
            XCTAssertEqual(deadline.confidence, .needsReview, deadline.kind.rawValue)
            XCTAssertTrue(deadline.note.contains("공휴일 표"), deadline.kind.rawValue)
        }
    }

    func testDeadlinesAreSortedByDueDate() throws {
        let deadlines = try calendar().deadlines(year: 2026, taxpayer: Taxpayer(withholding: .monthly))
        let dates = deadlines.map(\.dueDate)
        XCTAssertEqual(dates, dates.sorted())
    }
}
