import XCTest
import MoneyLedgerModels
@testable import MoneyLedgerModels

final class MoneyAmountTests: XCTestCase {
    func testKRWParsing() throws {
        XCTAssertEqual(try MoneyAmount.minorUnits(from: "15000", currency: "KRW"), 15000)
        XCTAssertEqual(try MoneyAmount.minorUnits(from: "1,500,000", currency: "KRW"), 1_500_000)
        XCTAssertEqual(try MoneyAmount.minorUnits(from: "₩15,000", currency: "KRW"), 15000)
        XCTAssertEqual(try MoneyAmount.minorUnits(from: "-15000", currency: "krw"), -15000)
        XCTAssertEqual(try MoneyAmount.minorUnits(from: "(1,500)", currency: "KRW"), -1500)
    }

    func testUSDParsing() throws {
        XCTAssertEqual(try MoneyAmount.minorUnits(from: "15.99", currency: "USD"), 1599)
        XCTAssertEqual(try MoneyAmount.minorUnits(from: "$20", currency: "USD"), 2000)
        XCTAssertEqual(try MoneyAmount.minorUnits(from: "-0.50", currency: "USD"), -50)
    }

    func testRejectsFractionForKRW() {
        XCTAssertThrowsError(try MoneyAmount.minorUnits(from: "150.5", currency: "KRW"))
    }

    func testRejectsGarbage() {
        XCTAssertThrowsError(try MoneyAmount.minorUnits(from: "abc", currency: "KRW"))
        XCTAssertThrowsError(try MoneyAmount.minorUnits(from: "", currency: "KRW"))
    }

    func testFormatting() {
        XCTAssertEqual(MoneyAmount.format(minor: 1_500_000, currency: "KRW"), "₩1,500,000")
        XCTAssertEqual(MoneyAmount.format(minor: -15000, currency: "KRW"), "-₩15,000")
        XCTAssertEqual(MoneyAmount.format(minor: 1599, currency: "USD"), "$15.99")
        XCTAssertEqual(MoneyAmount.format(minor: -50, currency: "USD"), "-$0.50")
    }

    func testCurrencyNormalization() {
        XCTAssertEqual(MoneyAmount.normalizedCurrency("원"), "KRW")
        XCTAssertEqual(MoneyAmount.normalizedCurrency(" usd "), "USD")
        XCTAssertEqual(MoneyAmount.normalizedCurrency(""), "KRW")
    }
}
