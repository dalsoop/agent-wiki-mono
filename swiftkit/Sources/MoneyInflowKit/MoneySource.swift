import Foundation

/// 돈 유입원의 종류. 가족 앱 하나가 하나의 원천 종류를 담당한다.
public enum MoneySourceType: String, Codable, Sendable, CaseIterable {
    case governmentProgram
    case loan
    case subsidy
    case taxBenefit

    public var displayName: String {
        switch self {
        case .governmentProgram: return "정부 지원사업"
        case .loan: return "정책 · 서민 대출"
        case .subsidy: return "보조금 · 지원금"
        case .taxBenefit: return "조세지원 · 감면"
        }
    }
}

/// 돈이 들어오는 모든 정보 원천의 공통 계약.
/// 각 가족 앱이 자기 데이터 원천 DTO 를 이 프로토콜로 사상(map)한다 — 매칭은 계약 기반으로 돌아서,
/// 원천 포맷이 바뀌어도 매칭 엔진은 그대로다.
public protocol MoneySource: Identifiable, Sendable {
    /// 고유 식별자(원천 ID 권장).
    var id: String { get }
    /// 공고 · 상품명.
    var title: String { get }
    /// 소관/수행/발급 기관명.
    var providerName: String { get }
    /// 한 줄 요약(사업개요/상품요약).
    var summary: String { get }
    /// 원천 종류.
    var sourceType: MoneySourceType { get }
    /// 해당 분야(비어있으면 분야 무관).
    var categories: Set<SupportCategory> { get }
    /// 해당 지역(비어있으면 전국).
    var regions: Set<KoreanRegion> { get }
    /// 지원대상 원문 — 비즈니스 유형 매칭에 사용.
    var targetAudienceText: String { get }
    /// 신청 · 접수 기간.
    var period: ApplicationPeriod { get }
    /// 상세/신청 페이지 URL.
    var detailURL: URL? { get }
    /// 신청(접수) 진입 URL — 상세 페이지와 다를 수 있다.
    var applyURL: URL? { get }
}

/// 매칭 편의 — 프로토콜 기본 구현은 독립 파일에 둘 수 없어 여기에.
public extension MoneySource {
    /// 마감까지 남은 일수(없으면 nil).
    func daysUntilClose(now: Date = Date()) -> Int? {
        period.daysUntilClose(now: now)
    }

    /// 지금 접수 중인가.
    var isAcceptingNow: Bool { period.isAcceptingNow() }
}
