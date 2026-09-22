import XCTest
import MoneyLedgerModels
@testable import KoreanTaxRulesKit

final class InputVATDeductibilityTests: XCTestCase {
    private func judge(
        _ evidence: EvidenceKind,
        _ counterparty: CounterpartyKind,
        purpose: PurchasePurpose = .general
    ) -> InputVATDeductibility.Judgement {
        InputVATDeductibility.judge(evidence: evidence, counterpartyKind: counterparty, purpose: purpose)
    }

    func testQualifiedEvidenceFromGeneralTaxpayerIsDeductible() {
        XCTAssertEqual(judge(.taxInvoice, .generalTaxpayer), .deductible)
        XCTAssertEqual(judge(.electronicTaxInvoice, .generalTaxpayer), .deductible)
        XCTAssertEqual(judge(.cashReceiptExpense, .generalTaxpayer), .deductible)
        XCTAssertEqual(judge(.businessCreditCard, .generalTaxpayer), .deductible)
    }

    func testSimplifiedTaxpayerNeedsReview() {
        XCTAssertEqual(judge(.businessCreditCard, .simplifiedTaxpayer), .needsReview(.simplifiedTaxpayerCardSlip))
        XCTAssertEqual(judge(.cashReceiptExpense, .simplifiedTaxpayer), .needsReview(.simplifiedTaxpayerCardSlip))
        XCTAssertEqual(judge(.taxInvoice, .simplifiedTaxpayer), .needsReview(.simplifiedTaxpayerInvoiceEligibility))
    }

    func testUnknownCounterparty() {
        XCTAssertEqual(judge(.businessCreditCard, .unknown), .needsReview(.unknownCounterparty))
        // 세금계산서는 발급 자체가 과세 거래의 증거다.
        XCTAssertEqual(judge(.taxInvoice, .unknown), .deductible)
    }

    func testNonDeductibleCounterparties() {
        XCTAssertEqual(judge(.businessCreditCard, .foreignBusiness), .nonDeductible(.foreignSupplierNoKoreanVAT))
        XCTAssertEqual(judge(.foreignInvoice, .foreignBusiness), .nonDeductible(.foreignSupplierNoKoreanVAT))
        XCTAssertEqual(judge(.taxInvoice, .taxExemptBusiness), .nonDeductible(.taxExemptSupplier))
        XCTAssertEqual(judge(.businessCreditCard, .nonBusinessIndividual), .nonDeductible(.nonBusinessSeller))
    }

    func testInadequateEvidence() {
        XCTAssertEqual(judge(.simpleReceipt, .generalTaxpayer), .nonDeductible(.inadequateEvidence))
        XCTAssertEqual(judge(.foreignInvoice, .unknown), .nonDeductible(.foreignSupplierNoKoreanVAT))
        XCTAssertEqual(judge(.estimatedSplit, .generalTaxpayer), .needsReview(.estimatedSplitNeedsEvidence))
        XCTAssertEqual(judge(.exportEvidence, .generalTaxpayer), .needsReview(.salesEvidenceOnPurchase))
    }

    func testPurposeOverridesEverything() {
        XCTAssertEqual(judge(.taxInvoice, .generalTaxpayer, purpose: .entertainment), .nonDeductible(.entertainmentExpense))
        XCTAssertEqual(judge(.electronicTaxInvoice, .generalTaxpayer, purpose: .nonBusiness), .nonDeductible(.nonBusinessUse))
        XCTAssertEqual(
            judge(.businessCreditCard, .generalTaxpayer, purpose: .nonBusinessPassengerVehicle),
            .nonDeductible(.nonBusinessPassengerVehicle)
        )
        XCTAssertEqual(judge(.taxInvoice, .generalTaxpayer, purpose: .taxExemptBusinessUse), .nonDeductible(.taxExemptBusinessUse))
    }

    func testJudgementAccessorsAndLabels() {
        let judgement = judge(.simpleReceipt, .generalTaxpayer)
        XCTAssertFalse(judgement.isDeductible)
        XCTAssertEqual(judgement.reason, .inadequateEvidence)
        XCTAssertTrue(judgement.label(korean: true).hasPrefix("불공제"))
        XCTAssertTrue(judgement.label(korean: false).hasPrefix("Non-deductible"))
        XCTAssertTrue(InputVATDeductibility.Judgement.deductible.isDeductible)
        XCTAssertNil(InputVATDeductibility.Judgement.deductible.reason)
        for reason in InputVATDeductibility.Reason.allCases {
            XCTAssertFalse(reason.label(korean: true).isEmpty)
            XCTAssertFalse(reason.label(korean: false).isEmpty)
        }
    }

    func testEvidenceQualification() {
        XCTAssertTrue(EvidenceKind.taxInvoice.isQualified)
        XCTAssertTrue(EvidenceKind.businessCreditCard.isQualified)
        XCTAssertFalse(EvidenceKind.simpleReceipt.isQualified)
        XCTAssertFalse(EvidenceKind.estimatedSplit.isQualified)
    }
}
