import Foundation

/// 도메인 중립 온라인 기회/공고/딜 항목 모델
/// 정부지원사업, R&D 공고, SaaS 구독 할인, 바우처 등 모든 기회 신호를 단일 규격으로 수용
public struct OpportunityIntelItem: Codable, Sendable, Identifiable, Equatable {
    /// 고유 식별자 (예: "kstartup:2026:ai-voucher", "chatgpt:pro:vnd")
    public var id: String
    /// 제공 주체/기관명 (예: "중소벤처기업부", "OpenAI", "Anthropic", "IITP")
    public var provider: String
    /// 정규화된 서비스/프로그램 식별자 (소문자, 예: "k-startup", "chatgpt")
    public var canonical: String
    /// 기회/공고/딜 제목
    public var title: String
    /// 상세 요약 또는 지원/할인 혜택 설명
    public var summary: String
    /// 공식 신청/상세 링크 (정규화 완료된 절대 URL)
    public var url: String
    /// 출처 테넌트/카테고리 (예: "gov-grants", "subscription-deals")
    public var category: String
    /// 정가 또는 총 사업비 (원문 문자열, 예: "총 사업비 5,000만원", "$200/mo")
    public var standardValue: String?
    /// 체감 실부담금 또는 지원금/할인가 (예: "정부지원금 4,500만원", "$10/mo")
    public var actualValue: String?
    /// 할인율 또는 지원 비율 (0~100%, 예: 90, 50)
    public var discountOrSupportRate: Int?
    /// 쿠폰/프로모션 코드 또는 접수/공고 번호 (원클릭 복사용)
    public var opportunityCode: String?
    /// 마감일 (YYYY-MM-DD 또는 ISO8601)
    public var deadline: String?
    /// 신청 자격요건 또는 전제조건 (예: "창업 3년 이내", "VPN 우회 및 해외카드")
    public var prerequisites: String?
    /// 정부지원사업: 자부담 비율 또는 금액 (예: "자부담 10% (현금 500만원)", "20%")
    public var selfPayRatio: String?
    /// 정부지원사업/딜: 모집 대상 (예: "인공지능(AI)/SW 분야 초기 스타트업")
    public var targetAudience: String?
    /// 신뢰도 점수 (0~100)
    public var score: Int
    /// 생존 상태
    public var liveness: OpportunityLiveness
    /// 최초 발견 일자 (YYYY-MM-DD)
    public var firstSeen: String
    /// 최종 확인 일자 (YYYY-MM-DD)
    public var lastSeen: String
    /// 특화 키워드 태그 (예: ["R&D", "바우처", "청년창업"])
    public var tags: [String]

    public init(
        id: String,
        provider: String,
        canonical: String? = nil,
        title: String,
        summary: String,
        url: String,
        category: String,
        standardValue: String? = nil,
        actualValue: String? = nil,
        discountOrSupportRate: Int? = nil,
        opportunityCode: String? = nil,
        deadline: String? = nil,
        prerequisites: String? = nil,
        selfPayRatio: String? = nil,
        targetAudience: String? = nil,
        score: Int = 80,
        liveness: OpportunityLiveness = .alive,
        firstSeen: String = ISO8601DateFormatter().string(from: Date()).prefix(10).description,
        lastSeen: String = ISO8601DateFormatter().string(from: Date()).prefix(10).description,
        tags: [String] = []
    ) {
        self.id = id
        self.provider = provider
        self.canonical = canonical ?? provider.lowercased()
        self.title = title
        self.summary = summary
        self.url = url
        self.category = category
        self.standardValue = standardValue
        self.actualValue = actualValue
        self.discountOrSupportRate = discountOrSupportRate
        self.opportunityCode = opportunityCode
        self.deadline = deadline
        self.prerequisites = prerequisites
        self.selfPayRatio = selfPayRatio
        self.targetAudience = targetAudience
        self.score = score
        self.liveness = liveness
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
        self.tags = tags
    }

    /// 정부지원사업 공고 여부 자동 감지
    public var isGovGrant: Bool {
        let cat = category.lowercased()
        if cat.contains("gov") || cat.contains("grant") {
            return true
        }
        if selfPayRatio != nil || targetAudience != nil {
            return true
        }
        let grantKeywords = ["중소벤처기업부", "창업진흥원", "기획평가원", "기술보증기금", "신용보증기금", "진흥원", "지원사업", "모집공고", "바우처", "R&D", "연구개발", "정부지원"]
        return grantKeywords.contains { provider.contains($0) || title.contains($0) }
    }

    enum CodingKeys: String, CodingKey {
        case id, provider, canonical, title, summary, url, category
        case standardValue, actualValue, discountOrSupportRate, opportunityCode
        case deadline, prerequisites, selfPayRatio, targetAudience
        case score, liveness, firstSeen, lastSeen, tags
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        provider = try container.decode(String.self, forKey: .provider)
        canonical = try container.decodeIfPresent(String.self, forKey: .canonical) ?? provider.lowercased()
        title = try container.decode(String.self, forKey: .title)
        summary = try container.decode(String.self, forKey: .summary)
        url = try container.decode(String.self, forKey: .url)
        category = try container.decode(String.self, forKey: .category)
        standardValue = try container.decodeIfPresent(String.self, forKey: .standardValue)
        actualValue = try container.decodeIfPresent(String.self, forKey: .actualValue)
        discountOrSupportRate = try container.decodeIfPresent(Int.self, forKey: .discountOrSupportRate)
        opportunityCode = try container.decodeIfPresent(String.self, forKey: .opportunityCode)
        deadline = try container.decodeIfPresent(String.self, forKey: .deadline)
        prerequisites = try container.decodeIfPresent(String.self, forKey: .prerequisites)
        selfPayRatio = try container.decodeIfPresent(String.self, forKey: .selfPayRatio)
        targetAudience = try container.decodeIfPresent(String.self, forKey: .targetAudience)
        score = try container.decodeIfPresent(Int.self, forKey: .score) ?? 80
        liveness = try container.decodeIfPresent(OpportunityLiveness.self, forKey: .liveness) ?? .alive
        firstSeen = try container.decodeIfPresent(String.self, forKey: .firstSeen) ?? ""
        lastSeen = try container.decodeIfPresent(String.self, forKey: .lastSeen) ?? ""
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
    }
}

/// 기회의 생존/유효성 상태
public enum OpportunityLiveness: String, Codable, Sendable, CaseIterable {
    /// 정상 유효 / 신청 가능 / 즉시 탑승 가능
    case alive = "alive"
    /// 주의 / 마감 임박 (D-3 이내) 또는 막힘/예산소진 보고 접수
    case caution = "caution"
    /// 마감됨 / 예산 소진 / 프로모션 종료
    case expired = "expired"
    /// 링크 깨짐 / 404 / 접근 불가
    case dead = "dead"

    public var displayBadge: String {
        switch self {
        case .alive: return "🟢 접수가능"
        case .caution: return "🟡 마감임박/주의"
        case .expired: return "🔴 마감됨"
        case .dead: return "⚫ 확인불가"
        }
    }
}
