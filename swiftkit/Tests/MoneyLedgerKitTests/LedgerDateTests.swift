import XCTest
import MoneyLedgerModels
@testable import MoneyLedgerModels

final class LedgerDateTests: XCTestCase {
    func testNormalizeVariants() throws {
        XCTAssertEqual(try LedgerDate.normalize("2026-08-04").date, "2026-08-04")
        XCTAssertEqual(try LedgerDate.normalize("2026.08.04").date, "2026-08-04")
        XCTAssertEqual(try LedgerDate.normalize("2026/8/4").date, "2026-08-04")
        XCTAssertEqual(try LedgerDate.normalize("26-08-04").date, "2026-08-04")
    }

    func testNormalizeWithTime() throws {
        let result = try LedgerDate.normalize("2026-08-04 13:22:01")
        XCTAssertEqual(result.date, "2026-08-04")
        XCTAssertEqual(result.time, "13:22:01")
    }

    func testNormalizeTime() {
        XCTAssertEqual(LedgerDate.normalizeTime("13:22"), "13:22:00")
        XCTAssertEqual(LedgerDate.normalizeTime("132201"), "13:22:01")
        XCTAssertNil(LedgerDate.normalizeTime("99:99"))
        XCTAssertNil(LedgerDate.normalizeTime("abc"))
    }

    func testRejectsGarbage() {
        XCTAssertThrowsError(try LedgerDate.normalize("2026-13-01"))
        XCTAssertThrowsError(try LedgerDate.normalize("어제"))
        XCTAssertThrowsError(try LedgerDate.normalize(""))
    }

    func testAdvance() {
        XCTAssertEqual(LedgerDate.advance("2026-01-31", by: .monthly), "2026-02-28")
        XCTAssertEqual(LedgerDate.advance("2026-08-04", by: .yearly), "2027-08-04")
        XCTAssertNil(LedgerDate.advance("2026-08-04", by: .oneTime))
    }

    func testMonthRange() throws {
        let range = try LedgerDate.monthRange("2026-08")
        XCTAssertEqual(range.from, "2026-08-01")
        XCTAssertTrue("2026-08-31" <= range.to)
        XCTAssertTrue("2026-09-01" > range.to)
    }
}
