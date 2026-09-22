import XCTest
import MoneyLedgerModels
@testable import KoreanTaxRulesKit

final class VATSplitTests: XCTestCase {
    func testSplitTruncatesWonFraction() {
        let result = VATSplit.split(grossMinor: 11_111)
        XCTAssertEqual(result.vatMinor, 1_010)  // 11,111 × 10 ÷ 110 = 1,010.09 → 절사
        XCTAssertEqual(result.supplyMinor, 10_101)
        XCTAssertEqual(result.grossMinor, 11_111)
        XCTAssertEqual(result.supplyMinor + result.vatMinor, result.grossMinor)
    }

    func testSplitExactAmounts() {
        let result = VATSplit.split(grossMinor: 110_000)
        XCTAssertEqual(result.vatMinor, 10_000)
        XCTAssertEqual(result.supplyMinor, 100_000)
        XCTAssertEqual(VATSplit.split(grossMinor: 0), VATSplit.Result(grossMinor: 0, supplyMinor: 0, vatMinor: 0))
    }

    func testRefundIsSymmetric() {
        let sale = VATSplit.split(grossMinor: 11_111)
        let refund = VATSplit.split(grossMinor: -11_111)
        XCTAssertEqual(refund.vatMinor, -sale.vatMinor)
        XCTAssertEqual(refund.supplyMinor, -sale.supplyMinor)
    }

    func testGrossFromSupply() {
        let result = VATSplit.gross(supplyMinor: 10_000)
        XCTAssertEqual(result.vatMinor, 1_000)
        XCTAssertEqual(result.grossMinor, 11_000)

        let odd = VATSplit.gross(supplyMinor: 10_101)
        XCTAssertEqual(odd.vatMinor, 1_010)
        XCTAssertEqual(odd.grossMinor, 11_111)
    }
}
