import Foundation

// 결정적 매칭 점수 + 사람이 읽는 사유. LLM 아님 — 4축(대상·지역·분야·기간) 규칙에서 산출.
// 좋은 매칭 서비스(Poliflo 등)의 핵심 UX: "왜 이 사업이 나에게 매칭됐는지"를 점수+사유로 보여준다.
// 점수는 매칭 강도 + 마감 임박도의 합으로, 매칭 통과한 항목만 채점한다.

public struct MatchScore: Sendable, Equatable {
    public let score: Int            // 0~100 (높을수록 잘 맞음/긴급)
    public let reasons: [String]     // "소상공인 대상", "서울 지역", "접수중 D-21" …
    public init(score: Int, reasons: [String]) {
        self.score = max(0, min(100, score))
        self.reasons = reasons
    }
}

/// 매칭 결과 한 건(소스 + 점수/사유). 가족 앱 UI 의 ForEach/선택 에 쓰인다.
public struct MatchedItem: Identifiable, Sendable {
    public let source: any MoneySource
    public let score: MatchScore
    public var id: String { source.id }
    public init(source: any MoneySource, score: MatchScore) {
        self.source = source; self.score = score
    }
}

/// 정렬 모드 — 점수순(기본) / 마감순.
public enum SortMode: Sendable { case score, deadline }

public extension MoneySourceMatcher {
    /// 단일 소스의 매칭 점수 + 사유. (매칭 통과 여부와 무관하게 채점 가능)
    func score(_ source: any MoneySource, profile: ApplicantProfile, now: Date = Date()) -> MatchScore {
        var s = 30
        var reasons = [String]()

        // — 대상(비즈니스 유형)
        let explicitTypes = matchedBusinessTypes(source, profile)
        let profileHasTypes = !profile.businessTypes.isEmpty && !profile.businessTypes.contains(.general)
        if !profileHasTypes {
            s += 5
        } else if let first = explicitTypes.first {
            s += 20
            reasons.append("\(first.displayName) 대상")
        } else if !hasSpecificTarget(source) {
            s += 8
            reasons.append("누구나 신청 가능")
        }

        // — 분야
        if profile.categories.isEmpty {
            s += 5
        } else if !source.categories.isDisjoint(with: profile.categories) {
            s += 12
            if let c = profile.categories.first(where: { source.categories.contains($0) }) {
                reasons.append("\(c.displayName) 분야")
            }
        } else if source.categories.isEmpty {
            s += 5
        }

        // — 지역
        if profile.region == .nationwide {
            s += 5
        } else if source.regions.contains(profile.region) {
            s += 12
            reasons.append("\(profile.region.displayName) 지역")
        } else if source.regions.isEmpty || source.regions.contains(.nationwide) {
            s += 6
            reasons.append("전국")
        }

        // — 기간(마감 임박도)
        if let d = source.period.daysUntilClose(now: now) {
            if d < 0 {
                s += 0
            } else if d == 0 {
                s += 18; reasons.append("오늘 마감")
            } else if d <= 3 {
                s += 18; reasons.append("마감임박 D-\(d)")
            } else if d <= 7 {
                s += 12; reasons.append("접수중 D-\(d)")
            } else if d <= 14 {
                s += 6; reasons.append("접수중 D-\(d)")
            } else {
                s += 2; reasons.append("접수중 D-\(d)")
            }
        } else {
            s += 3
            reasons.append("상시 모집")
        }

        return MatchScore(score: s, reasons: reasons)
    }

    /// 매칭 통과 항목만 채점해 점수 내림차순으로 반환(동점이면 마감 빠른 순).
    func matchScored(
        _ sources: [any MoneySource],
        profile: ApplicantProfile,
        includeClosed: Bool = false,
        now: Date = Date()
    ) -> [(source: any MoneySource, score: MatchScore)] {
        filter(sources, profile: profile, includeClosed: includeClosed, now: now)
            .map { ($0, score($0, profile: profile, now: now)) }
            .sorted { lhs, rhs in
                lhs.score.score != rhs.score.score
                    ? lhs.score.score > rhs.score.score
                    : (lhs.source.period.daysUntilClose(now: now) ?? Int.max) < (rhs.source.period.daysUntilClose(now: now) ?? Int.max)
            }
    }

    // MARK: - 내부 보조

    /// 소스가 프로필의 어떤 비즈니스 유형에 명시적으로 해당하는지(키워드 매칭).
    func matchedBusinessTypes(_ source: any MoneySource, _ profile: ApplicantProfile) -> [BusinessType] {
        let text = source.targetAudienceText
        return profile.businessTypes.filter { type in
            type != .general && type.matchKeywords.contains { text.contains($0) }
        }
    }

    /// 소스가 특정 대상을 명시하는지(어떤 유형 키워드도 없으면 누구나).
    func hasSpecificTarget(_ source: any MoneySource) -> Bool {
        let text = source.targetAudienceText
        return BusinessType.allCases.contains { type in
            type != .general && type.matchKeywords.contains { text.contains($0) }
        }
    }
}
