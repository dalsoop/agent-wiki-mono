import Foundation

/// 라이선스 상태에 따른 앱 접근 수준.
public enum AccessLevel: String, Codable, Sendable, Equatable {
    /// 정상 결제 중(active, trialing, past_due). 모든 기능 사용 가능.
    case full
    /// 결제 유예 만료(unpaid). 기존 데이터 읽기만 가능, 새 작업·업데이트 차단.
    case readOnly
    /// 구독 해지·만료(canceled, expired). 앱 실행 차단.
    case blocked
}
