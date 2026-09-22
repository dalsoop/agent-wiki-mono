import Foundation

/// 결정적 매칭 엔진 — "지금 내 상태에 맞는" 소스만 걸러 정렬한다.
/// 규칙은 세 가지 축: 접수중(기간) · 대상(비즈니스 유형) · 지역 · 분야.
/// LLM 이 아닌 규칙 기반이다 — 판단이 들어가면 안 되는 결정적 작업은 코드로(Post 참고).
public struct MoneySourceMatcher: Sendable {
    public init() {}

    /// 프로필에 해당하는 소스만 필터. includeClosed=false(기본)면 현재 접수중인 것만.
    public func filter(
        _ sources: [any MoneySource],
        profile: ApplicantProfile,
        includeClosed: Bool = false,
        now: Date = Date()
    ) -> [any MoneySource] {
        sources.filter { source in
            (includeClosed || source.period.isAcceptingNow(now: now))
                && matchesCategories(source, profile)
                && matchesRegion(source, profile)
                && matchesTarget(source, profile)
        }
    }

    /// 마감임박순 정렬. 마감일 모르는 것은 뒤로.
    public func sortByDeadline(_ sources: [any MoneySource], now: Date = Date()) -> [any MoneySource] {
        sources.sorted { lhs, rhs in
            key(source: lhs, now: now) < key(source: rhs, now: now)
        }
    }

    /// 필터 + 정렬 한 번에.
    public func match(
        _ sources: [any MoneySource],
        profile: ApplicantProfile,
        includeClosed: Bool = false,
        now: Date = Date()
    ) -> [any MoneySource] {
        sortByDeadline(filter(sources, profile: profile, includeClosed: includeClosed, now: now), now: now)
    }

    // MARK: - 축별 판정

    /// 분야: 프로필이 분야를 안 고른 경우 전체 허용. 소스가 분야 무관(빈 집합)이어도 허용.
    func matchesCategories(_ source: any MoneySource, _ profile: ApplicantProfile) -> Bool {
        if profile.categories.isEmpty { return true }
        if source.categories.isEmpty { return true }
        return !source.categories.isDisjoint(with: profile.categories)
    }

    /// 지역: 프로필이 전국이거나 소스가 전국(빈 집합)이면 허용. 아니면 교집합 또는 원문 키워드.
    func matchesRegion(_ source: any MoneySource, _ profile: ApplicantProfile) -> Bool {
        if profile.region == .nationwide { return true }
        if source.regions.isEmpty || source.regions.contains(.nationwide) { return true }
        if source.regions.contains(profile.region) { return true }
        // 원문에 지역 키워드가 명시돼 있으면 그것으로 보강 판정.
        let text = source.targetAudienceText + " " + source.summary
        return profile.region.matchKeywords.contains { text.localizedContains($0) }
    }

    /// 대상(비즈니스 유형):
    /// - 프로필에 .general 포함 → 전체 허용("일반"=전체 보기 모드).
    /// - 소스가 특정 대상을 명시하지 않으면(어떤 유형 키워드도 없으면) → 누구나 허용.
    /// - 그 외: 소스 대상 원문이 프로필 유형 중 하나라도 명시하면 허용.
    func matchesTarget(_ source: any MoneySource, _ profile: ApplicantProfile) -> Bool {
        if profile.businessTypes.contains(.general) { return true }
        if profile.businessTypes.isEmpty { return true }
        let text = source.targetAudienceText
        let anySpecific = BusinessType.allCases.contains { type in
            type != .general && type.matchKeywords.contains { text.localizedContains($0) }
        }
        if !anySpecific { return true } // 명시 대상 제한 없음 = 누구나
        return profile.businessTypes.contains { type in
            type != .general && type.matchKeywords.contains { text.localizedContains($0) }
        }
    }

    private func key(source: any MoneySource, now: Date) -> Int {
        guard let days = source.period.daysUntilClose(now: now) else { return Int.max }
        return days < 0 ? Int.max - 1 : days // 이미 마감도 뒤로(무한대보단 앞).
    }
}

// MARK: - 문자열 포함(대소문자 무관 Unicode)

extension String {
    /// 단순 부분문자열 포함(한국어엔 대소문아 의미 없지만 영토큰 대비).
    func localizedContains(_ other: String) -> Bool {
        range(of: other) != nil
    }
}
