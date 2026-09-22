import Foundation

/// 기준값·판정 규칙의 확신도. 법령 원문·관보로 확인한 값은 `confirmed`, 기준 연도나 개정 여부를
/// 아직 대조하지 못한 값은 `needsReview` 다. 소비 앱은 needsReview 를 화면·CLI 에 그대로 드러내고,
/// 지어낸 숫자로 신고 일정·의무를 단정하지 않는다(위키 9261be4f "확신 없는 숫자는 needsReview").
public enum RuleConfidence: String, Codable, Sendable, CaseIterable {
    case confirmed
    case needsReview

    public func label(korean: Bool) -> String {
        switch self {
        case .confirmed: korean ? "확인됨" : "confirmed"
        case .needsReview: korean ? "검토 필요" : "needs review"
        }
    }

    /// 둘 중 낮은 확신도. 규칙과 데이터를 합성한 판정은 어느 한쪽이 검토 필요면 전체가 검토 필요다.
    public func merged(with other: RuleConfidence) -> RuleConfidence {
        self == .confirmed && other == .confirmed ? .confirmed : .needsReview
    }
}
