import XCTest
import MoneyLedgerModels
@testable import KoreanTaxRulesKit

final class ObligationTests: XCTestCase {
    // MARK: 간편장부 / 복식부기

    func testNewBusinessFirstYearIsSimplifiedLedger() throws {
        let judgement = try BookkeepingObligation.judge(
            year: 2026, industryGroup: .manufacturingConstructionInformation, priorYearRevenueMinor: nil, isNewBusiness: true
        )
        XCTAssertEqual(judgement.obligation, .simplifiedLedger)
        XCTAssertEqual(judgement.confidence, .confirmed)
        XCTAssertNil(judgement.thresholdMinor)
    }

    func testInformationIndustryThresholdIsMarkedNeedsReview() throws {
        let below = try BookkeepingObligation.judge(
            year: 2026, industryGroup: .manufacturingConstructionInformation, priorYearRevenueMinor: 100_000_000, isNewBusiness: false
        )
        XCTAssertEqual(below.obligation, .simplifiedLedger)
        XCTAssertEqual(below.thresholdMinor, 150_000_000)
        XCTAssertEqual(below.confidence, .needsReview)
        XCTAssertEqual(below.basisYear, 2026)

        let atThreshold = try BookkeepingObligation.judge(
            year: 2027, industryGroup: .manufacturingConstructionInformation, priorYearRevenueMinor: 150_000_000, isNewBusiness: false
        )
        XCTAssertEqual(atThreshold.obligation, .doubleEntry)
        XCTAssertEqual(atThreshold.basisYear, 2026, "2027 표가 없으면 2026 표가 이월된다")
    }

    func testProfessionalsAlwaysDoubleEntry() throws {
        let judgement = try BookkeepingObligation.judge(
            year: 2026, industryGroup: .professionalService, priorYearRevenueMinor: nil, isNewBusiness: true
        )
        XCTAssertEqual(judgement.obligation, .doubleEntry)
        XCTAssertEqual(judgement.confidence, .confirmed)
    }

    func testMissingPriorRevenueWithoutNewFlagNeedsReview() throws {
        let judgement = try BookkeepingObligation.judge(
            year: 2026, industryGroup: .realEstateRentalAndServices, priorYearRevenueMinor: nil, isNewBusiness: false
        )
        XCTAssertEqual(judgement.obligation, .simplifiedLedger)
        XCTAssertEqual(judgement.confidence, .needsReview)
    }

    func testYearBeforeTableThrows() {
        XCTAssertThrowsError(try BookkeepingObligation.judge(
            year: 1990, industryGroup: .agricultureWholesaleRetail, priorYearRevenueMinor: 0, isNewBusiness: false
        )) { error in
            XCTAssertEqual(error as? TaxRuleResourceError, .noRuleForYear(resource: BookkeepingObligation.resourceName, year: 1990))
        }
    }

    // MARK: 성실신고확인대상

    func testSincereReportingInformationIndustry() throws {
        let subject = try SincereReportingObligation.judge(
            year: 2026, industryGroup: .manufacturingConstructionInformation, revenueMinor: 750_000_000
        )
        XCTAssertTrue(subject.isSubject)
        XCTAssertEqual(subject.thresholdMinor, 750_000_000)
        XCTAssertEqual(subject.confidence, .needsReview)

        let below = try SincereReportingObligation.judge(
            year: 2026, industryGroup: .manufacturingConstructionInformation, revenueMinor: 749_999_999
        )
        XCTAssertFalse(below.isSubject)
    }

    // MARK: 전자세금계산서 의무발급

    func testElectronicTaxInvoiceEightyMillionFrom2024July() throws {
        let obligated = try ElectronicTaxInvoiceObligation.judge(priorYear: 2025, priorYearSupplyMinor: 80_000_000)
        XCTAssertTrue(obligated.isObligated)
        XCTAssertEqual(obligated.obligationFrom, "2026-07-01")
        XCTAssertEqual(obligated.obligationTo, "2027-06-30")
        XCTAssertEqual(obligated.thresholdMinor, 80_000_000)
        XCTAssertEqual(obligated.thresholdEffectiveFrom, "2024-07-01")
        XCTAssertEqual(obligated.confidence, .confirmed)

        let below = try ElectronicTaxInvoiceObligation.judge(priorYear: 2025, priorYearSupplyMinor: 79_999_999)
        XCTAssertFalse(below.isObligated)

        let newBusiness = try ElectronicTaxInvoiceObligation.judge(priorYear: 2025, priorYearSupplyMinor: nil)
        XCTAssertFalse(newBusiness.isObligated)
    }

    func testElectronicTaxInvoiceHistoricalThresholds() throws {
        XCTAssertEqual(try ElectronicTaxInvoiceObligation.judge(priorYear: 2022, priorYearSupplyMinor: 0).thresholdMinor, 100_000_000)
        XCTAssertEqual(try ElectronicTaxInvoiceObligation.judge(priorYear: 2021, priorYearSupplyMinor: 0).thresholdMinor, 200_000_000)
        XCTAssertThrowsError(try ElectronicTaxInvoiceObligation.judge(priorYear: 2010, priorYearSupplyMinor: 0))
    }

    // MARK: 현금영수증 의무발행업종

    func testCashReceiptMandatoryIndustries() throws {
        let lawyer = try CashReceiptMandatoryIssuance.judge(industry: "변호사업")
        XCTAssertTrue(lawyer.isMandatoryIndustry)
        XCTAssertTrue(lawyer.isListed)
        XCTAssertEqual(lawyer.confidence, .confirmed)
        XCTAssertEqual(lawyer.mandatoryAmountMinor, 100_000)

        let software = try CashReceiptMandatoryIssuance.judge(industry: "소프트웨어 개발 및 공급업")
        XCTAssertFalse(software.isMandatoryIndustry)
        XCTAssertTrue(software.isListed)
        XCTAssertEqual(software.confidence, .needsReview)

        let unlisted = try CashReceiptMandatoryIssuance.judge(industry: "완전히 모르는 업종")
        XCTAssertFalse(unlisted.isMandatoryIndustry)
        XCTAssertFalse(unlisted.isListed)
        XCTAssertEqual(unlisted.confidence, .needsReview)
    }

    func testCashReceiptIssuanceThreshold() throws {
        XCTAssertTrue(try CashReceiptMandatoryIssuance.requiresIssuance(industry: "변호사업", amountMinor: 100_000))
        XCTAssertFalse(try CashReceiptMandatoryIssuance.requiresIssuance(industry: "변호사업", amountMinor: 99_999))
        XCTAssertFalse(try CashReceiptMandatoryIssuance.requiresIssuance(industry: "소프트웨어 개발 및 공급업", amountMinor: 1_000_000))
        // 이름 정규화: 공백·쉼표 차이를 무시한다.
        XCTAssertTrue(try CashReceiptMandatoryIssuance.judge(industry: "컴퓨터 및 주변장치·소프트웨어 소매업").isListed)
    }

    func testYearKeyedResolvesLatestYearAtOrBelow() {
        let table = YearKeyed(byYear: [2020: "a", 2024: "b"])
        XCTAssertEqual(table.resolve(year: 2026)?.value, "b")
        XCTAssertEqual(table.resolve(year: 2026)?.year, 2024)
        XCTAssertEqual(table.resolve(year: 2023)?.value, "a")
        XCTAssertNil(table.resolve(year: 2019))
    }
}
