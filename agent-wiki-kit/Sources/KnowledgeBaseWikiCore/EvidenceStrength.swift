import Foundation

/// 근거 강화 모델 — SwarmVault 검증 공식의 이식.
/// 지지도 = 포화곡선(재현 수) × 감쇠(마지막 재현 이후 반감), 반박은 별도 축으로 보존.
public struct EvidenceStrength: Sendable, Equatable {
    /// 이 근거를 supports/재현으로 인용한 수.
    public let supportCount: Int
    /// contradicts/반박 인용 수.
    public let contradictCount: Int
    /// 마지막 재확인(발행 또는 최신 supports) 시각.
    public let lastReinforcedAt: Date
    /// 0~1. confidence(포화) × decay(반감).
    public let score: Double
    /// 0~1 감쇠만 — UI 의 "바램" 표현용.
    public let freshness: Double

    /// 반감기 90일 (제3자 근거 기준 — SwarmVault third_party 와 동일).
    public static let halfLifeDays: Double = 90

    public init(supportCount: Int, contradictCount: Int, lastReinforcedAt: Date, now: Date = Date()) {
        self.supportCount = supportCount
        self.contradictCount = contradictCount
        self.lastReinforcedAt = lastReinforcedAt
        // 포화곡선: 0개=0.5, 1개=0.65 … cap 0.95 (nodeConfidence 이식)
        let confidence = min(0.5 + Double(supportCount) * 0.15, 0.95)
        let days = max(0, now.timeIntervalSince(lastReinforcedAt) / 86_400)
        let decay = pow(0.5, days / Self.halfLifeDays)
        self.freshness = decay
        self.score = confidence * decay
    }

    /// 강화 이벤트 판정에 쓰는 rel 어휘 — Argdown 표준(supports/contradicts/undercuts) 채택.
    public static let supportRels: Set<String> = ["supports", "재현", "restores"]
    public static let contradictRels: Set<String> = ["contradicts", "undercuts", "반박"]
}

extension LedgerStore {
    /// 계보(lineage) 전체에 대한 강화 상태 — 어느 판을 인용했든 그 근거의 강화로 친다.
    public func strength(_ objects: [LedgerObject], of head: LedgerObject, now: Date = Date()) -> EvidenceStrength {
        let lineageIDs = Set(lineage(objects, of: head.id).map(\.id))
        var supports = 0
        var contradicts = 0
        var lastReinforced = head.published
        for object in objects where !lineageIDs.contains(object.id) {
            for cite in object.cites where lineageIDs.contains(cite.id) {
                if EvidenceStrength.supportRels.contains(cite.rel) {
                    supports += 1
                    lastReinforced = max(lastReinforced, object.published)
                } else if EvidenceStrength.contradictRels.contains(cite.rel) {
                    contradicts += 1
                }
            }
        }
        return EvidenceStrength(
            supportCount: supports, contradictCount: contradicts,
            lastReinforcedAt: lastReinforced, now: now)
    }
}
