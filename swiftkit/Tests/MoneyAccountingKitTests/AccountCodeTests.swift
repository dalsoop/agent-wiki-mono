import XCTest
import MoneyLedgerModels
@testable import MoneyAccountingKit

final class AccountCodeTests: XCTestCase {
    func testEveryCodeHasDescriptorAndBothLabels() {
        for code in AccountCode.allCases {
            let descriptor = code.descriptor
            XCTAssertFalse(descriptor.korean.isEmpty, code.rawValue)
            XCTAssertFalse(descriptor.english.isEmpty, code.rawValue)
            XCTAssertEqual(code.label(korean: true), descriptor.korean)
            XCTAssertEqual(code.label(korean: false), descriptor.english)
        }
    }

    func testSectionCountsFollowStandardIncomeStatement() {
        XCTAssertEqual(AccountCode.codes(in: .revenue).count, 1)
        XCTAssertEqual(AccountCode.codes(in: .costOfSales).count, 3)
        XCTAssertEqual(AccountCode.codes(in: .sellingAndAdministrative).count, 20)
        XCTAssertEqual(AccountCode.codes(in: .nonOperatingIncome).count, 3)
        XCTAssertEqual(AccountCode.codes(in: .nonOperatingExpense).count, 4)
        XCTAssertEqual(AccountCode.codes(in: .capitalTransaction).count, 4)
        XCTAssertEqual(AccountCode.allCases.count, 35)
    }

    func testGujoCostOfSalesCodes() {
        XCTAssertEqual(AccountCode.aiApiUsage.section, .costOfSales)
        XCTAssertEqual(AccountCode.hostingAndCloud.section, .costOfSales)
        XCTAssertEqual(AccountCode.purchases.section, .costOfSales)
        // PG 수수료는 판관비 지급수수료다.
        XCTAssertEqual(AccountCode.fees.section, .sellingAndAdministrative)
    }

    func testCapitalTransactionsDoNotAffectIncome() {
        for code in AccountCode.codes(in: .capitalTransaction) {
            XCTAssertFalse(code.section.affectsIncome, code.rawValue)
            XCTAssertEqual(code.section.incomeSign, 0)
        }
        XCTAssertEqual(AccountSection.revenue.incomeSign, 1)
        XCTAssertEqual(AccountSection.costOfSales.incomeSign, -1)
    }

    func testResolveByRawOrLabel() {
        XCTAssertEqual(AccountCode.resolve("fees"), .fees)
        XCTAssertEqual(AccountCode.resolve("지급수수료"), .fees)
        XCTAssertEqual(AccountCode.resolve(" Fees and commissions "), .fees)
        XCTAssertEqual(AccountCode.resolve("AI API 사용료"), .aiApiUsage)
        XCTAssertNil(AccountCode.resolve("식비"))
        XCTAssertNil(AccountCode.resolve(""))
    }

    func testDisplayOrderFollowsDeclaration() {
        XCTAssertLessThan(AccountCode.sales.displayOrder, AccountCode.purchases.displayOrder)
        XCTAssertLessThan(AccountCode.miscellaneousExpense.displayOrder, AccountCode.interestIncome.displayOrder)
    }
}
