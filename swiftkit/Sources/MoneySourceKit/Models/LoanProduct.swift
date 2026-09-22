import Foundation
import MoneyInflowKit

public enum KinfaSite {
    /// 서민금융진흥원(KINFA) 공개 페이지 호스트. 전체 origin 은 아래에서 조립한다.
    public static let host = "www.kinfa.or.kr"
    public static let origin = "https://" + host
    public static var home: URL { URL(string: origin)! }
    public static func page(_ path: String) -> URL {
        URL(string: "\(origin)\(path)")!
    }
}

public struct LoanProduct: MoneySource, Codable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let providerName: String
    public let summary: String
    public var sourceType: MoneySourceType { .loan }
    public let categories: Set<SupportCategory>
    public let regions: Set<KoreanRegion>
    public let targetAudienceText: String
    public let period: ApplicationPeriod
    public let detailURL: URL?
    public let applyURL: URL?

    // 대출 부가 표시 필드
    public let interestRate: String   // "연 4.5% ~ 5.0%"
    public let maxAmount: String      // "최대 1,500만 원"
    public let eligibilityNote: String // 자격 요건 한 줄

    public init(
        id: String, title: String, providerName: String, summary: String,
        categories: Set<SupportCategory>, regions: Set<KoreanRegion>,
        targetAudienceText: String, period: ApplicationPeriod,
        detailURL: URL?, applyURL: URL?,
        interestRate: String, maxAmount: String, eligibilityNote: String
    ) {
        self.id = id; self.title = title; self.providerName = providerName; self.summary = summary
        self.categories = categories; self.regions = regions
        self.targetAudienceText = targetAudienceText; self.period = period
        self.detailURL = detailURL; self.applyURL = applyURL
        self.interestRate = interestRate; self.maxAmount = maxAmount; self.eligibilityNote = eligibilityNote
    }
}

extension LoanProduct {
    /// 서민금융 주요 상품(서민금융진흥원 KINFA · 공공데이터 서비스 15074508 계열).
    public static let catalog: [LoanProduct] = [
        LoanProduct(
            id: "kinfa-worker-haepsal",
            title: "근로자햇살론",
            providerName: "서민금융진흥원 · 은행",
            summary: "직장을 다니는 저신용·저소득 근로자를 위한 저리 생활안정자금 대출.",
            categories: [.finance], regions: [],
            targetAudienceText: "근로자(직장인) 중 신용점수 낮은 저소득자. 연소득 4,500만 원 이하(외벌이)/3,500만 원 이하(단독).",
            period: ApplicationPeriod(start: nil, end: nil, rawText: "상시 모집"),
            detailURL: KinfaSite.page("/haepsal/worker.do"),
            applyURL: KinfaSite.page("/haepsal/worker.do"),
            interestRate: "연 4.5% ~ 5.0%",
            maxAmount: "최대 1,500만 원",
            eligibilityNote: "재직 3개월 이상 근로자, 신용·소득 요건 충족"
        ),
        LoanProduct(
            id: "kinfa-haepsal15",
            title: "햇살론15",
            providerName: "서민금융진흥원 · 은행",
            summary: "신용등급 하위 10% 저신용자의 생활안정자금. 햇살론 대체 상품.",
            categories: [.finance], regions: [],
            targetAudienceText: "신용점수 하위 10% 이하. 연소득 4,500만 원 이하(외벌이)/3,500만 원 이하(단독).",
            period: ApplicationPeriod(start: nil, end: nil, rawText: "상시 모집"),
            detailURL: KinfaSite.page("/haepsal/haepsal15.do"),
            applyURL: KinfaSite.page("/haepsal/haepsal15.do"),
            interestRate: "연 4.5%",
            maxAmount: "최대 1,500만 원",
            eligibilityNote: "저신용·저소득 개인, 연체 30일 이내"
        ),
        LoanProduct(
            id: "kinfa-haepsal-youth",
            title: "햇살론유스(청년향상형)",
            providerName: "서민금융진흥원 · 은행",
            summary: "청년 근로자의 취업·생활안정을 위한 저리 대출(취업 후 상환).",
            categories: [.finance], regions: [],
            targetAudienceText: "청년(만 19~34세) 근로자. 연소득 3,500만 원 이하(단독)/4,500만 원 이하(외벌이).",
            period: ApplicationPeriod(start: nil, end: nil, rawText: "상시 모집"),
            detailURL: KinfaSite.page("/haepsal/youth.do"),
            applyURL: KinfaSite.page("/haepsal/youth.do"),
            interestRate: "연 3.5% ~ 4.5%",
            maxAmount: "최대 1,200만 원",
            eligibilityNote: "만 19~34세 청년 근로자, 소득 요건 충족"
        ),
        LoanProduct(
            id: "kinfa-microfinance",
            title: "미소금융(창업·운영자금)",
            providerName: "서민금융진흥원",
            summary: "저소득 영세 소상공인의 창업·사업운영 자금을 저리로 대출(대리반환 지원).",
            categories: [.finance], regions: [],
            targetAudienceText: "저소득 영세 소상공인. 사업장 소재지 기준 차상위계층 이하.",
            period: ApplicationPeriod(start: nil, end: nil, rawText: "상시 모집"),
            detailURL: KinfaSite.page("/microfinance/main.do"),
            applyURL: KinfaSite.page("/microfinance/apply.do"),
            interestRate: "연 3.0% ~ 4.5%",
            maxAmount: "최대 5,000만 원",
            eligibilityNote: "영세 소상공인, 신용·소득 요건 충족"
        ),
        LoanProduct(
            id: "kinfa-youth-account",
            title: "청년도약계좌",
            providerName: "금융위원회 · 서민금융진흥원",
            summary: "청년의 자산형성을 돕는 정부 매칭 적립식 저축.",
            categories: [.finance], regions: [],
            targetAudienceText: "청년(만 19~34세). 근로·사업소득 3,600만 원 이하(외벌이)/2,400만 원 이하(단독).",
            period: ApplicationPeriod(start: nil, end: nil, rawText: "연 중 모집(분기 접수)"),
            detailURL: KinfaSite.page("/youthaccount/main.do"),
            applyURL: KinfaSite.page("/youthaccount/apply.do"),
            interestRate: "정부 기여금 6%",
            maxAmount: "월 70만 원 적립(5년)",
            eligibilityNote: "만 19~34세 청년, 소득 요건 충족"
        ),
        LoanProduct(
            id: "kinfa-dream-seed",
            title: "새희망씨앗(긴급자금)",
            providerName: "서민금융진흥원",
            summary: "긴급자금·대환(기존 고금리 대출 전환)이 필요한 영세 소상공인 대상 저리 자금.",
            categories: [.finance], regions: [],
            targetAudienceText: "긴급자금 또는 대환이 필요한 저소득 영세 소상공인.",
            period: ApplicationPeriod(start: nil, end: nil, rawText: "상시 모집"),
            detailURL: KinfaSite.page("/microfinance/seed.do"),
            applyURL: KinfaSite.page("/microfinance/seed.do"),
            interestRate: "연 4.5% (1년 무이자 가능)",
            maxAmount: "최대 5,000만 원",
            eligibilityNote: "영세 소상공인, 대환·긴급자금 사유"
        ),
    ]
}
