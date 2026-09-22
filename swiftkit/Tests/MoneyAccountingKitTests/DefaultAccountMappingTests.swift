import XCTest
import MoneyLedgerModels
@testable import MoneyAccountingKit

final class DefaultAccountMappingTests: XCTestCase {
    private func mapping() throws -> DefaultAccountMapping {
        try DefaultAccountMapping.loadBundled()
    }

    func testBundledTableLoadsAndEveryRuleIsAnnotated() throws {
        let table = try mapping()
        XCTAssertEqual(table.version, 1)
        XCTAssertFalse(table.rules.isEmpty)
        for rule in table.rules {
            XCTAssertFalse(rule.note.isEmpty, rule.id)
            XCTAssertFalse(rule.categories.isEmpty && rule.descriptionPatterns.isEmpty, "\(rule.id) 에 매칭 조건이 없다")
        }
        XCTAssertEqual(Set(table.rules.map(\.id)).count, table.rules.count, "규칙 id 중복")
    }

    func testGujoCostOfSalesSuggestions() throws {
        let table = try mapping()
        let openai = try XCTUnwrap(table.suggest(category: nil, description: "OpenAI *API usage", flow: .outflow))
        XCTAssertEqual(openai.accountCode, .aiApiUsage)
        XCTAssertEqual(openai.confidence, .confirmed)
        XCTAssertEqual(openai.match, .description("openai"))

        XCTAssertEqual(table.suggest(category: nil, description: "ANTHROPIC, PBC", flow: .outflow)?.accountCode, .aiApiUsage)
        XCTAssertEqual(table.suggest(category: nil, description: "AWS EMEA", flow: .outflow)?.accountCode, .hostingAndCloud)
        XCTAssertEqual(table.suggest(category: nil, description: "Cloudflare", flow: .outflow)?.accountCode, .hostingAndCloud)
    }

    func testPGFeeIsFeesAndSettlementIsSales() throws {
        let table = try mapping()
        let fee = try XCTUnwrap(table.suggest(category: nil, description: "나이스페이먼츠 수수료", flow: .outflow))
        XCTAssertEqual(fee.accountCode, .fees)
        XCTAssertEqual(fee.confidence, .confirmed)

        let settlement = try XCTUnwrap(table.suggest(category: nil, description: "나이스페이 정산", flow: .inflow))
        XCTAssertEqual(settlement.accountCode, .sales)
        XCTAssertEqual(settlement.confidence, .needsReview)

        XCTAssertEqual(table.suggest(category: nil, description: "PayPal fee", flow: .outflow)?.accountCode, .fees)
        XCTAssertEqual(table.suggest(category: nil, description: "PAYPAL 정산", flow: .inflow)?.accountCode, .sales)
    }

    func testFlowDisambiguatesInterest() throws {
        let table = try mapping()
        XCTAssertEqual(table.suggest(category: nil, description: "예금 이자", flow: .inflow)?.accountCode, .interestIncome)
        XCTAssertEqual(table.suggest(category: nil, description: "대출 이자", flow: .outflow)?.accountCode, .interestExpense)
        // 방향을 모르면 표 순서대로 첫 규칙 — 방향 규칙을 건너뛰지 않는다.
        XCTAssertNotNil(table.suggest(category: nil, description: "이자"))
    }

    func testCategoryLabelWinsBeforeTable() throws {
        let table = try mapping()
        let byLabel = try XCTUnwrap(table.suggest(category: "지급수수료", description: "OpenAI"))
        XCTAssertEqual(byLabel.accountCode, .fees)
        XCTAssertEqual(byLabel.ruleID, DefaultAccountMapping.accountLabelRuleID)
        XCTAssertEqual(byLabel.match, .accountLabel("지급수수료"))

        let byCategory = try XCTUnwrap(table.suggest(category: "PG수수료", description: "무관", flow: .outflow))
        XCTAssertEqual(byCategory.accountCode, .fees)
        XCTAssertEqual(byCategory.match, .category("PG수수료"))
    }

    func testTaxPaymentsSuggestOwnerDrawingWithReview() throws {
        let table = try mapping()
        let vat = try XCTUnwrap(table.suggest(category: nil, description: "부가가치세 납부", flow: .outflow))
        XCTAssertEqual(vat.accountCode, .ownerDrawing)
        XCTAssertEqual(vat.confidence, .needsReview)
    }

    func testUnknownReturnsNil() throws {
        let table = try mapping()
        XCTAssertNil(table.suggest(category: nil, description: "알 수 없는 거래"))
        XCTAssertNil(table.suggest(category: "식비", description: ""))
    }

    func testInMemoryRulesRespectOrder() {
        let table = DefaultAccountMapping(rules: [
            .init(id: "first", accountCode: .advertising, descriptionPatterns: ["google"], confidence: .confirmed, note: "n"),
            .init(id: "second", accountCode: .hostingAndCloud, descriptionPatterns: ["google cloud"], confidence: .confirmed, note: "n"),
        ])
        XCTAssertEqual(table.suggest(category: nil, description: "Google Cloud")?.ruleID, "first")
    }
}
