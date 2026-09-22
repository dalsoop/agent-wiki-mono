import XCTest
import MoneyInflowKit
@testable import MoneySourceKit

final class MoneySourceKitTests: XCTestCase {
    func testCatalogUniqueness() {
        let subsidyIDs = SubsidyProgram.catalog.map(\.id)
        XCTAssertEqual(Set(subsidyIDs).count, subsidyIDs.count)

        let loanIDs = LoanProduct.catalog.map(\.id)
        XCTAssertEqual(Set(loanIDs).count, loanIDs.count)

        let taxIDs = TaxBenefit.catalog.map(\.id)
        XCTAssertEqual(Set(taxIDs).count, taxIDs.count)
    }

    func testGovernmentProgramSample() {
        XCTAssertEqual(GovernmentProgram.sample.count, 4)
        let sampleIDs = GovernmentProgram.sample.map(\.id)
        XCTAssertEqual(Set(sampleIDs).count, sampleIDs.count)
    }

    func testAttachmentParser() {
        let html = """
        <a href="/cmm/fms/fileDown.do?atchFileId=FILE_000000000738721&fileSn=0" \
        class="x" target="_blank" title="첨부파일 1.+2026년+참여기업+모집+공고.hwp 다운로드">다운로드</a>
        <a href="/cmm/fms/fileDown.do?atchFileId=FILE_000000000738722&fileSn=0" \
        title="첨부파일 2.+매뉴얼.pdf 다운로드">다운로드</a>
        """
        let parsed = BizInfoAttachmentParser.parse(html: html)
        XCTAssertEqual(parsed.count, 2)
        XCTAssertEqual(parsed.filter(\.isHangulForm).count, 1)
        XCTAssertTrue(parsed.contains(where: { $0.fileName.contains(".hwp") }))
    }

    func testEndpoints() {
        let url = BizInfoEndpoints.crawlPageURL(3).absoluteString
        XCTAssertTrue(url.contains("cpage=3"))
        XCTAssertFalse(url.contains("pageIndex="))
    }

    func testConfigStores() throws {
        let testProfile = ApplicantProfile(businessTypes: [.soho], region: .seoul, categories: [.finance])
        let cfg = MoneySourceProfileConfig(profile: testProfile, crtfcKey: "test-key")
        XCTAssertEqual(cfg.profile.region, .seoul)
        XCTAssertEqual(cfg.crtfcKey, "test-key")
    }

    func testMatcherOnCatalogs() {
        let matcher = MoneySourceMatcher()

        // Youth profile matching subsidy
        let subsidyYouth = matcher.match(SubsidyProgram.catalog, profile: ApplicantProfile(businessTypes: [.youth]))
        XCTAssertFalse(subsidyYouth.isEmpty)

        // SOHO profile matching loans
        let sohoLoan = matcher.match(LoanProduct.catalog, profile: ApplicantProfile(businessTypes: [.soho]))
        XCTAssertFalse(sohoLoan.isEmpty)

        // SME profile matching tax benefit
        let smeTax = matcher.match(TaxBenefit.catalog, profile: ApplicantProfile(businessTypes: [.sme]))
        XCTAssertFalse(smeTax.isEmpty)
    }
}
