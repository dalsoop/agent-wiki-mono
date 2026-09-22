import Foundation
import MoneyInflowKit

public enum TaxBenefitOfficialLinks {
    public static let nts = URL(string: "https://www.nts.go.kr/")!
    public static let homeTax = URL(string: "https://www.hometax.go.kr/")!
}

public struct TaxBenefit: MoneySource, Codable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let providerName: String
    public let summary: String
    public var sourceType: MoneySourceType { .taxBenefit }
    public let categories: Set<SupportCategory>
    public let regions: Set<KoreanRegion>
    public let targetAudienceText: String
    public let period: ApplicationPeriod
    public let detailURL: URL?
    public let applyURL: URL?

    public let benefitAmount: String     // "소득세 30% 감면(3년)"
    public let eligibilityNote: String

    public init(
        id: String, title: String, providerName: String, summary: String,
        categories: Set<SupportCategory>, regions: Set<KoreanRegion>,
        targetAudienceText: String, period: ApplicationPeriod,
        detailURL: URL?, applyURL: URL?,
        benefitAmount: String, eligibilityNote: String
    ) {
        self.id = id; self.title = title; self.providerName = providerName; self.summary = summary
        self.categories = categories; self.regions = regions
        self.targetAudienceText = targetAudienceText; self.period = period
        self.detailURL = detailURL; self.applyURL = applyURL
        self.benefitAmount = benefitAmount; self.eligibilityNote = eligibilityNote
    }
}

public enum TaxBenefitCatalogCopy {
    public static let provider = "기획재정부 · 국세청"
    public static let alwaysOnPeriod = ApplicationPeriod(start: nil, end: nil, rawText: "상시(과세기간 확정신고)")
}

extension TaxBenefit {
    /// 주요 조세지원 제도(조세특례제한법). 상시 적용(과세기간 신청).
    public static let catalog: [TaxBenefit] = [
        TaxBenefit(
            id: "nts-sme-special-reduction",
            title: "중소기업 특별세액감면",
            providerName: TaxBenefitCatalogCopy.provider,
            summary: "수도권 외 중소기업(제조·지식서비스업 등)의 소득에 대해 소득세·법인세를 감면.",
            categories: [.management, .finance], regions: [],
            targetAudienceText: "중소기업(수도권 외 제조업, 지식기반서비스업 등). 규모·업종 요건.",
            period: TaxBenefitCatalogCopy.alwaysOnPeriod,
            detailURL: TaxBenefitOfficialLinks.nts,
            applyURL: TaxBenefitOfficialLinks.homeTax,
            benefitAmount: "소득세 5% ~ 30% 감면",
            eligibilityNote: "중소기업 해당업종, 수도권 외(예외 있음)"
        ),
        TaxBenefit(
            id: "nts-startup-sme-reduction",
            title: "창업중소기업 세액감면",
            providerName: TaxBenefitCatalogCopy.provider,
            summary: "창업중소기업의 당해 소득에 대해 창업 후 일정 기간 세액을 감면.",
            categories: [.management, .startup], regions: [],
            targetAudienceText: "창업중소기업(창업일 기준 5년 이내, 해당업종).",
            period: TaxBenefitCatalogCopy.alwaysOnPeriod,
            detailURL: TaxBenefitOfficialLinks.nts,
            applyURL: TaxBenefitOfficialLinks.homeTax,
            benefitAmount: "당해·2년 50%~100% 감면, 이후 3년 50% 감면",
            eligibilityNote: "창업중소기업, 업종·규모 요건"
        ),
        TaxBenefit(
            id: "nts-integrated-investment-credit",
            title: "통합투자세액공제",
            providerName: TaxBenefitCatalogCopy.provider,
            summary: "사업용 자산(시설투자 등)에 투자한 금액의 일정 비율을 세액공제.",
            categories: [.management, .technology], regions: [],
            targetAudienceText: "사업용 자산에 투자하는 중소기업(업종별 공제율 차등).",
            period: TaxBenefitCatalogCopy.alwaysOnPeriod,
            detailURL: TaxBenefitOfficialLinks.nts,
            applyURL: TaxBenefitOfficialLinks.homeTax,
            benefitAmount: "투자금의 1% ~ 25% 세액공제",
            eligibilityNote: "사업용 신규자산 투자, 업종별 요건"
        ),
        TaxBenefit(
            id: "nts-youth-employment-credit",
            title: "청년고용증대 세액공제",
            providerName: TaxBenefitCatalogCopy.provider,
            summary: "전년도 대비 청년 고용을 늘린 기업에 청년 1인당 세액공제.",
            categories: [.workforce, .management], regions: [],
            targetAudienceText: "만 15~29세 청년 고용을 늘린 중소기업(우선지원대상기업).",
            period: TaxBenefitCatalogCopy.alwaysOnPeriod,
            detailURL: TaxBenefitOfficialLinks.nts,
            applyURL: TaxBenefitOfficialLinks.homeTax,
            benefitAmount: "청년 1인당 연 700~900만 원 세액공제(3년)",
            eligibilityNote: "청년 순증, 중소기업 요건"
        ),
        TaxBenefit(
            id: "nts-angel-investment-deduction",
            title: "엔젤투자 소득공제",
            providerName: TaxBenefitCatalogCopy.provider,
            summary: "벤처기업·창업기업에 투자한 투자자의 투자금 소득공제 및 양도차익 감면.",
            categories: [.finance, .startup], regions: [],
            targetAudienceText: "벤처기업·창업중소기업(창업기업)에 투자하는 개인투자자.",
            period: TaxBenefitCatalogCopy.alwaysOnPeriod,
            detailURL: TaxBenefitOfficialLinks.nts,
            applyURL: TaxBenefitOfficialLinks.homeTax,
            benefitAmount: "투자금 30% 소득공제 / 양도차익 70% 감면",
            eligibilityNote: "창업·벤처기업 투자, 요건 충족"
        ),
        TaxBenefit(
            id: "nts-woman-enterprise-reduction",
            title: "여성기업 세액감면",
            providerName: TaxBenefitCatalogCopy.provider,
            summary: "여성기업(여성 대표·직원 비중)의 소득에 대해 세액감면(일부 지역·업종).",
            categories: [.management], regions: [],
            targetAudienceText: "여성기업(여성 대표자·임직원 비중 요건).",
            period: TaxBenefitCatalogCopy.alwaysOnPeriod,
            detailURL: TaxBenefitOfficialLinks.nts,
            applyURL: TaxBenefitOfficialLinks.homeTax,
            benefitAmount: "소득세 30% 감면(해당 업종)",
            eligibilityNote: "여성기업 요건, 해당업종"
        ),
    ]
}
