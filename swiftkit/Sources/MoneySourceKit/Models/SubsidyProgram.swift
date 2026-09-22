import Foundation
import MoneyInflowKit

public enum SubsidyOfficialURL {
    public static let ministryOfEmployment = URL(string: "https://www.moel.go.kr/")
    public static let work24 = URL(string: "https://www.work24.go.kr/")
    public static let youthTomorrow = URL(string: "https://www.sbc-plan.or.kr/")
}

public struct SubsidyProgram: MoneySource, Codable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let providerName: String
    public let summary: String
    public var sourceType: MoneySourceType { .subsidy }
    public let categories: Set<SupportCategory>
    public let regions: Set<KoreanRegion>
    public let targetAudienceText: String
    public let period: ApplicationPeriod
    public let detailURL: URL?
    public let applyURL: URL?

    public let supportAmount: String     // "월 60만 원 × 최대 6개월"
    public let eligibilityNote: String

    public init(
        id: String, title: String, providerName: String, summary: String,
        categories: Set<SupportCategory>, regions: Set<KoreanRegion>,
        targetAudienceText: String, period: ApplicationPeriod,
        detailURL: URL?, applyURL: URL?,
        supportAmount: String, eligibilityNote: String
    ) {
        self.id = id; self.title = title; self.providerName = providerName; self.summary = summary
        self.categories = categories; self.regions = regions
        self.targetAudienceText = targetAudienceText; self.period = period
        self.detailURL = detailURL; self.applyURL = applyURL
        self.supportAmount = supportAmount; self.eligibilityNote = eligibilityNote
    }
}

extension SubsidyProgram {
    /// 고용지원금 주요 제도(고용노동부·한국산업인력공단 HRD). 상시 접수.
    public static let catalog: [SubsidyProgram] = [
        SubsidyProgram(
            id: "moel-youth-hire-incentive",
            title: "청년채용특별장려금",
            providerName: "고용노동부 · 고용센터",
            summary: "청년을 신규 채용한 중소·중견기업에 채용 6개월간 월 60만 원을 지원(최대 2년 연장 가능).",
            categories: [.workforce], regions: [],
            targetAudienceText: "만 15~29세 청년을 신규 채용하는 중소기업·중견기업.",
            period: ApplicationPeriod(start: nil, end: nil, rawText: "상시 접수"),
            detailURL: SubsidyOfficialURL.ministryOfEmployment,
            applyURL: SubsidyOfficialURL.work24,
            supportAmount: "월 60만 원 × 최대 6~24개월",
            eligibilityNote: "청년(15~29세) 신규채용, 6개월 의무고용"
        ),
        SubsidyProgram(
            id: "moel-youth-tomorrow-deduction",
            title: "청년내일채움공제",
            providerName: "고용노동부 · 중소기업중앙회",
            summary: "중소기업 청년 근로자의 장기근로 유도를 위한 적립식 공제(본인+기업+정부 적립).",
            categories: [.workforce], regions: [],
            targetAudienceText: "만 15~29세 청년으로 중소기업에 취업한 근로자(학력·소득 요건).",
            period: ApplicationPeriod(start: nil, end: nil, rawText: "수시 모집(분기별 접수)"),
            detailURL: SubsidyOfficialURL.ministryOfEmployment,
            applyURL: SubsidyOfficialURL.youthTomorrow,
            supportAmount: "2년 만기 시 최대 3,000만 원",
            eligibilityNote: "청년 중소기업 취업자, 2년 근로"
        ),
        SubsidyProgram(
            id: "moel-employment-creation",
            title: "고용창출지원금(고용장려금)",
            providerName: "고용노동부 · 고용센터",
            summary: "신규 채용으로 고용을 늘린 기업에 장려금 지원(업종·규모별 차등).",
            categories: [.workforce], regions: [],
            targetAudienceText: "신규 채용으로 고용이 증가한 중소기업(일부 전 산업).",
            period: ApplicationPeriod(start: nil, end: nil, rawText: "상시 접수"),
            detailURL: SubsidyOfficialURL.ministryOfEmployment,
            applyURL: SubsidyOfficialURL.work24,
            supportAmount: "월 40~120만 원 × 최대 2년",
            eligibilityNote: "정규직 신규채용, 고용증가 요건"
        ),
        SubsidyProgram(
            id: "moel-woman-reemployment",
            title: "여성재고용장려금",
            providerName: "고용노동부 · 고용센터",
            summary: "경력보유 여성(경력단절여성)을 재취업시킨 기업에 장려금 지원.",
            categories: [.workforce], regions: [],
            targetAudienceText: "경력보유 여성(경력단절여성)을 채용한 기업.",
            period: ApplicationPeriod(start: nil, end: nil, rawText: "상시 접수"),
            detailURL: SubsidyOfficialURL.ministryOfEmployment,
            applyURL: SubsidyOfficialURL.work24,
            supportAmount: "월 40~60만 원 × 최대 12개월",
            eligibilityNote: "여성 재취업, 6개월 의무고용"
        ),
        SubsidyProgram(
            id: "moel-employment-retention",
            title: "고용유지지원금",
            providerName: "고용노동부 · 고용센터",
            summary: "경영상 위기로 휴업·감축경영을 하는 기업이 고용을 유지할 때 지원.",
            categories: [.finance, .workforce], regions: [],
            targetAudienceText: "경영상 위기(매출 감소 등)로 고용유지 조치를 하는 중소기업·우선지원대상기업.",
            period: ApplicationPeriod(start: nil, end: nil, rawText: "상시 접수"),
            detailURL: SubsidyOfficialURL.ministryOfEmployment,
            applyURL: SubsidyOfficialURL.work24,
            supportAmount: "휴업수당의 대부분(최대 2/3)",
            eligibilityNote: "고용유지 조치 승인, 위기 요건"
        ),
        SubsidyProgram(
            id: "moel-older-worker",
            title: "장년고용장려금",
            providerName: "고용노동부 · 고용센터",
            summary: "50세 이상 장년층을 신규 채용한 기업에 장려금 지원.",
            categories: [.workforce], regions: [],
            targetAudienceText: "만 50세 이상자를 신규 채용한 기업(우선지원대상기업).",
            period: ApplicationPeriod(start: nil, end: nil, rawText: "상시 접수"),
            detailURL: SubsidyOfficialURL.ministryOfEmployment,
            applyURL: SubsidyOfficialURL.work24,
            supportAmount: "월 30~90만 원 × 최대 2년",
            eligibilityNote: "50세 이상 신규채용, 의무고용"
        ),
    ]
}
