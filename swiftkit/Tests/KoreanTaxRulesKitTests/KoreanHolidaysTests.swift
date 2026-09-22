import XCTest
import MoneyLedgerModels
@testable import KoreanTaxRulesKit

final class KoreanHolidaysTests: XCTestCase {
    private func holidays() throws -> KoreanHolidays {
        try KoreanHolidays.loadBundled()
    }

    func testBundledTableCovers2026And2027WithLunarHolidays() throws {
        let table = try holidays()
        XCTAssertTrue(table.covers(year: 2026))
        XCTAssertTrue(table.covers(year: 2027))
        XCTAssertFalse(table.covers(year: 2030))
        XCTAssertEqual(table.holiday(on: "2026-02-17")?.name, "설날")
        XCTAssertEqual(table.holiday(on: "2026-05-24")?.name, "부처님오신날")
        XCTAssertEqual(table.holiday(on: "2026-09-25")?.name, "추석")
        XCTAssertEqual(table.holiday(on: "2027-02-06")?.name, "설날")
        XCTAssertEqual(table.holiday(on: "2027-09-15")?.name, "추석")
        XCTAssertEqual(table.holiday(on: "2026-06-03")?.kind, .election)
        XCTAssertEqual(table.holiday(on: "2026-05-01")?.kind, .laborDay)
        XCTAssertNil(table.holiday(on: "2026-07-21"))
    }

    func testEveryEntryIsWellFormed() throws {
        for entry in try holidays().entries {
            XCTAssertTrue(LedgerDate.isValid(entry.date), entry.date)
            XCTAssertFalse(entry.name.isEmpty, entry.date)
        }
    }

    func testWeekendAndBusinessDay() throws {
        let table = try holidays()
        XCTAssertTrue(table.isWeekend("2026-07-25"))  // 토
        XCTAssertTrue(table.isWeekend("2026-07-26"))  // 일
        XCTAssertFalse(table.isWeekend("2026-07-27"))
        XCTAssertTrue(table.isBusinessDay("2026-07-27"))
        XCTAssertFalse(table.isBusinessDay("2026-06-03"))  // 지방선거
        XCTAssertFalse(table.isBusinessDay("2026-05-01"))  // 근로자의 날 — 국세기본법 5조
    }

    func testRolloverSkipsWeekendsAndHolidays() throws {
        let table = try holidays()
        let saturday = try XCTUnwrap(table.rollover(from: "2026-07-25"))
        XCTAssertEqual(saturday.date, "2026-07-27")
        XCTAssertTrue(saturday.rolled)
        XCTAssertTrue(saturday.holidayTableCovered)
        XCTAssertEqual(saturday.reasons, ["주말", "주말"])

        // 3/1 일요일 → 3/2 대체공휴일 → 3/3
        XCTAssertEqual(table.rollover(from: "2026-03-01")?.date, "2026-03-03")
        // 근로자의 날(금) → 토·일 → 5/4
        XCTAssertEqual(table.rollover(from: "2026-05-01")?.date, "2026-05-04")
        // 2027 설날 연휴(금) → 토·일 → 대체공휴일(월) → 2/9
        XCTAssertEqual(table.rollover(from: "2027-02-05")?.date, "2027-02-09")
        // 영업일은 그대로
        let weekday = try XCTUnwrap(table.rollover(from: "2026-07-27"))
        XCTAssertEqual(weekday.date, "2026-07-27")
        XCTAssertFalse(weekday.rolled)
    }

    func testRolloverOutsideTableIsWeekendOnlyAndFlagged() throws {
        let table = try holidays()
        let rolled = try XCTUnwrap(table.rollover(from: "2030-07-27"))  // 2030-07-27 토요일
        XCTAssertEqual(rolled.date, "2030-07-29")
        XCTAssertFalse(rolled.holidayTableCovered)
        XCTAssertNil(table.rollover(from: "not-a-date"))
    }

    func testInMemoryTableWithoutEntries() {
        let empty = KoreanHolidays(source: "test", entries: [], coveredYears: [2026])
        XCTAssertTrue(empty.isBusinessDay("2026-03-02"))
        XCTAssertEqual(empty.rollover(from: "2026-03-01")?.date, "2026-03-02")
    }
}
