import Foundation
import OpportunityIntelKit

/// 어떤 앱에서든 즉시 UI 컴포넌트를 테스트하고 프리뷰할 수 있도록 제공하는 Mock 데이터셋
public enum OpportunityTimelineMockData {

    private static func mockURL(_ host: String, _ path: String = "") -> String {
        "https://\(host)\(path)"
    }

    /// 1. 정부지원사업 대표 예시 (중기부 AI 유니콘 육성사업)
    public static let govGrantAI = OpportunityIntelItem(
        id: "kstartup:2026:ai-unicorn",
        provider: "중소벤처기업부",
        canonical: "k-startup",
        title: "2026년 글로벌 AI 유니콘 육성 지원사업 창업기업 모집공고",
        summary: "생성형 AI 및 거대언어모델(LLM) 분야 유망 스타트업 대상 최대 5,000만원 사업화 자금 및 PoC 인프라 지원",
        url: mockURL("www.k-startup.go.kr"),
        category: "gov-grants",
        standardValue: "총 사업비 5,555만원",
        actualValue: "정부지원금 5,000만원",
        discountOrSupportRate: 90,
        opportunityCode: "공고 제2026-104호",
        deadline: ISO8601DateFormatter().string(from: Calendar.current.date(byAdding: .day, value: 3, to: Date()) ?? Date()).prefix(10).description,
        prerequisites: "창업 7년 이내 AI 모델 자체 개발 기업",
        selfPayRatio: "자부담 10% (현금 555만원)",
        targetAudience: "인공지능(AI)/SW 분야 초기·도약기 스타트업",
        score: 95,
        liveness: .caution,
        tags: ["바우처", "사업화", "자부담"]
    )

    /// 2. 정부지원사업 R&D 예시 (IITP 온디바이스 AI)
    public static let govGrantRnD = OpportunityIntelItem(
        id: "iitp:2026:ondevice-ai",
        provider: "정보통신기획평가원(IITP)",
        canonical: "iitp",
        title: "2026년 차세대 온디바이스 AI 핵심원천기술개발 R&D 신규과제 공고",
        summary: "경량화 온디바이스 AI 엣지 추론 엔진 및 NPU 최적화 기술 연구개발 지원",
        url: mockURL("www.iitp.kr"),
        category: "gov-grants",
        standardValue: "총 연구비 3.75억원",
        actualValue: "정부지원금 3억원",
        discountOrSupportRate: 80,
        opportunityCode: "과제번호 IITP-2026-042",
        deadline: ISO8601DateFormatter().string(from: Calendar.current.date(byAdding: .day, value: 25, to: Date()) ?? Date()).prefix(10).description,
        prerequisites: "기업부설연구소 또는 연구전담부서 보유 필수",
        selfPayRatio: "기관부담금 20% (현물 포함)",
        targetAudience: "국내 AI 솔루션 개발 중소·중견기업 컨소시엄",
        score: 90,
        liveness: .alive,
        tags: ["R&D", "자부담"]
    )

    /// 3. 온라인 딜 대표 예시 (Cursor AI Pro)
    public static let dealCursorPro = OpportunityIntelItem(
        id: "cursor:pro:annual-deal",
        provider: "Cursor AI",
        canonical: "cursor",
        title: "Cursor Pro 연간 플랜 신규 개발자 얼리버드 50% 특별 할인",
        summary: "고성능 차세대 AI 코드 자동완성 및 멀티파일 편집 지원 Pro 연간 구독 할인",
        url: mockURL("www.cursor.com", "/pricing"),
        category: "subscription-deals",
        standardValue: "$20/mo ($240/yr)",
        actualValue: "$10/mo",
        discountOrSupportRate: 50,
        opportunityCode: "CURSOR50",
        deadline: ISO8601DateFormatter().string(from: Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date()).prefix(10).description,
        prerequisites: "신규 가입자 한정 (해외결제 가능 카드)",
        score: 92,
        liveness: .alive,
        tags: ["해외우회", "Pro플래그십"]
    )

    /// 4. 온라인 딜 SaaS 예시 (ChatGPT Pro 요금제)
    public static let dealChatGPTPro = OpportunityIntelItem(
        id: "openai:chatgpt:pro-team",
        provider: "OpenAI",
        canonical: "chatgpt",
        title: "ChatGPT Pro 요금제 워크스페이스 팀 구독 30% 즉시 감면 프로모션",
        summary: "o1-pro 및 고급 데이터 분석, 음성 모드가 포함된 Pro 티어 프로모션",
        url: mockURL("chatgpt.com"),
        category: "subscription-deals",
        standardValue: "$200/mo",
        actualValue: "$140/mo",
        discountOrSupportRate: 30,
        opportunityCode: "PROTEAM30",
        deadline: ISO8601DateFormatter().string(from: Calendar.current.date(byAdding: .day, value: 2, to: Date()) ?? Date()).prefix(10).description,
        prerequisites: "워크스페이스 3인 이상 팀 플랜 동시 결제 시",
        score: 88,
        liveness: .caution,
        tags: ["Pro플래그십", "할인"]
    )

    /// 5. 마감된 공고 예시
    public static let expiredGrant = OpportunityIntelItem(
        id: "kstartup:2025:early-package",
        provider: "창업진흥원",
        canonical: "k-startup",
        title: "2025년 초기창업패키지 창업기업 모집 (접수마감)",
        summary: "3년 이내 초기창업기업 대상 사업화 자금 최대 1억원 지원",
        url: mockURL("www.k-startup.go.kr"),
        category: "gov-grants",
        standardValue: "총 사업비 1억원",
        actualValue: "지원금 1억원",
        discountOrSupportRate: 70,
        opportunityCode: "마감-2025-01",
        deadline: "2025-04-30",
        prerequisites: "창업 3년 이내",
        score: 60,
        liveness: .expired,
        tags: ["초기창업", "사업화"]
    )

    /// 3-Point 마일스톤 목업
    public static var govGrantMilestones: [OpportunityMilestone] {
        OpportunityScheduleAudit.generate3PointMilestones(
            firstSeen: govGrantAI.firstSeen,
            deadline: govGrantAI.deadline,
            actualValueText: govGrantAI.actualValue ?? "접수 시작",
            isGovGrant: true
        )
    }

    public static var dealMilestones: [OpportunityMilestone] {
        OpportunityScheduleAudit.generate3PointMilestones(
            firstSeen: dealCursorPro.firstSeen,
            deadline: dealCursorPro.deadline,
            actualValueText: dealCursorPro.actualValue ?? "프로모션 개시",
            isGovGrant: false
        )
    }
}
