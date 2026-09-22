import XCTest
@testable import MoneyInflowKit

/// "돈 들어오는 거 찾기" 공유 코어 테스트 — 기간 파싱(한국 날짜 변종)과 결정적 매칭 엔진.
/// 매칭은 LLM 이 아니라 규칙이므로, 규칙이 여기 고정된다.
final class MoneyInflowKitTests: XCTestCase {

    private let cal = ApplicationPeriod.gregorian

    private func makeDate(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    /// 날짜를 [년,월,일] 배열로(튜플은 Equatable 이 아니어서 비교 불가).
    private func ymd(_ d: Date?) -> [Int]? {
        guard let d else { return nil }
        let c = cal.dateComponents([.year, .month, .day], from: d)
        return [c.year ?? 0, c.month ?? 0, c.day ?? 0]
    }

    // MARK: - ApplicationPeriod 파싱

    func testParseCompactYYYYMMDD() {
        let p = ApplicationPeriod.parse("20250810~20250910")
        XCTAssertEqual(ymd(p.start), [2025, 8, 10])
        XCTAssertEqual(ymd(p.end), [2025, 9, 10])
    }

    func testParseDotSeparated() {
        let p = ApplicationPeriod.parse("2025.08.10~2025.09.10")
        XCTAssertEqual(ymd(p.start), [2025, 8, 10])
        XCTAssertEqual(ymd(p.end), [2025, 9, 10])
    }

    func testParseDashWithSpaces() {
        let p = ApplicationPeriod.parse("2025-08-10 ~ 2025-09-10")
        XCTAssertEqual(ymd(p.start), [2025, 8, 10])
        XCTAssertEqual(ymd(p.end), [2025, 9, 10])
    }

    func testParseKoreanWithInheritedYear() {
        // 끝쪽이 월·일만 있으면 시작 연도 승계.
        let p = ApplicationPeriod.parse("2025년 8월 10일 ~ 9월 10일")
        XCTAssertEqual(ymd(p.start), [2025, 8, 10])
        XCTAssertEqual(ymd(p.end), [2025, 9, 10])
    }

    func testParsePrefixedLabel() {
        let p = ApplicationPeriod.parse("접수기간 : 2025.08.10. ~ 09.10.")
        XCTAssertEqual(ymd(p.start), [2025, 8, 10])
        XCTAssertEqual(ymd(p.end), [2025, 9, 10])
    }

    func testParseEmptyReturnsNil() {
        let p = ApplicationPeriod.parse("")
        XCTAssertNil(p.start)
        XCTAssertNil(p.end)
        XCTAssertEqual(p.rawText, "")
    }

    func testParseGarbagePreservesRawText() {
        let p = ApplicationPeriod.parse("상시접수")
        XCTAssertNil(p.start)
        XCTAssertNil(p.end)
        XCTAssertEqual(p.rawText, "상시접수")
    }

    // MARK: - ApplicationPeriod 판정

    func testContainsAndDaysUntilClose() {
        let p = ApplicationPeriod(start: makeDate(2025, 8, 10), end: makeDate(2025, 8, 20), rawText: "")
        XCTAssertTrue(p.contains(makeDate(2025, 8, 15)))
        XCTAssertFalse(p.contains(makeDate(2025, 8, 9)))
        XCTAssertFalse(p.contains(makeDate(2025, 8, 21)))
        XCTAssertEqual(p.daysUntilClose(now: makeDate(2025, 8, 15)), 5)
        XCTAssertEqual(p.daysUntilClose(now: makeDate(2025, 8, 20)), 0)
        XCTAssertEqual(p.daysUntilClose(now: makeDate(2025, 8, 25)), -1) // 마감
    }

    func testUnknownEndDaysUntilCloseIsNil() {
        // end 미정 = 상시 모집 → 항상 접수중(daysUntilClose 는 알 수 없어 nil).
        let p = ApplicationPeriod(start: nil, end: nil, rawText: "상시접수")
        XCTAssertNil(p.daysUntilClose(now: makeDate(2025, 8, 15)))
        XCTAssertTrue(p.isAcceptingNow(now: makeDate(2025, 8, 15)))
    }

    // MARK: - 매칭 엔진

    private func source(
        id: String,
        target: String = "",
        categories: Set<SupportCategory> = [],
        regions: Set<KoreanRegion> = [],
        start: Date? = nil,
        end: Date? = nil,
        summary: String = ""
    ) -> any MoneySource {
        TestSource(
            id: id, title: id, providerName: "기관", summary: summary,
            sourceType: .governmentProgram, categories: categories, regions: regions,
            targetAudienceText: target,
            period: ApplicationPeriod(start: start, end: end, rawText: ""),
            detailURL: nil, applyURL: nil
        )
    }

    func testFilterExcludesClosedByDefault() {
        let now = makeDate(2025, 8, 15)
        let open = source(id: "open", start: makeDate(2025, 8, 10), end: makeDate(2025, 8, 20))
        let closed = source(id: "closed", start: makeDate(2025, 7, 1), end: makeDate(2025, 7, 31))
        let matcher = MoneySourceMatcher()
        let result = matcher.filter([open, closed], profile: .blank, now: now).map(\.id)
        XCTAssertEqual(result, ["open"])
        let all = matcher.filter([open, closed], profile: .blank, includeClosed: true, now: now).map(\.id)
        XCTAssertEqual(Set(all), ["open", "closed"])
    }

    func testTargetMatchSpecificAudience() {
        let m = MoneySourceMatcher()
        let soho = source(id: "s", target: "소상공인 및 일반소상공인")
        XCTAssertTrue(m.matchesTarget(soho, ApplicantProfile(businessTypes: [.soho])))
        XCTAssertFalse(m.matchesTarget(soho, ApplicantProfile(businessTypes: [.sme])))
    }

    func testTargetOpenToAllWhenNoSpecificKeyword() {
        let m = MoneySourceMatcher()
        let anyone = source(id: "a", target: "제한 없이 누구나 신청 가능")
        XCTAssertTrue(m.matchesTarget(anyone, ApplicantProfile(businessTypes: [.sme])))
        XCTAssertTrue(m.matchesTarget(anyone, ApplicantProfile(businessTypes: [.youth])))
    }

    func testGeneralProfileMatchesAll() {
        let m = MoneySourceMatcher()
        let specific = source(id: "x", target: "청년 창업기업")
        XCTAssertTrue(m.matchesTarget(specific, ApplicantProfile(businessTypes: [.general])))
    }

    func testRegionMatch() {
        let m = MoneySourceMatcher()
        let seoul = source(id: "seoul", regions: [.seoul])
        XCTAssertTrue(m.matchesRegion(seoul, ApplicantProfile(businessTypes: [], region: .seoul)))
        XCTAssertFalse(m.matchesRegion(seoul, ApplicantProfile(businessTypes: [], region: .busan)))
        // 전국 소스는 모든 지역에 매칭.
        let nat = source(id: "nat", regions: [])
        XCTAssertTrue(m.matchesRegion(nat, ApplicantProfile(businessTypes: [], region: .busan)))
    }

    func testCategoryMatch() {
        let m = MoneySourceMatcher()
        let startup = source(id: "su", categories: [.startup])
        // 프로필이 분야를 안 고르면 전체 허용.
        XCTAssertTrue(m.matchesCategories(startup, .blank))
        XCTAssertTrue(m.matchesCategories(startup, ApplicantProfile(categories: [.startup])))
        XCTAssertFalse(m.matchesCategories(startup, ApplicantProfile(categories: [.finance])))
    }

    func testSortByDeadlineAscending() {
        let now = makeDate(2025, 8, 15)
        let a = source(id: "far", start: makeDate(2025, 8, 10), end: makeDate(2025, 8, 30))   // 15일
        let b = source(id: "soon", start: makeDate(2025, 8, 10), end: makeDate(2025, 8, 17))  // 2일
        let c = source(id: "unknown", start: nil, end: nil)                                  // 알수없음 → 뒤
        let matcher = MoneySourceMatcher()
        let order = matcher.sortByDeadline([a, c, b], now: now).map(\.id)
        XCTAssertEqual(order, ["soon", "far", "unknown"])
    }

    func testMatchEndToEnd() {
        let now = makeDate(2025, 8, 15)
        let matcher = MoneySourceMatcher()
        let profile = ApplicantProfile(businessTypes: [.soho], region: .seoul, categories: [.finance])
        let sources: [any MoneySource] = [
            source(id: "hit", target: "서울 소상공인", categories: [.finance],
                   regions: [.seoul], start: makeDate(2025, 8, 10), end: makeDate(2025, 8, 20)),
            source(id: "wrongRegion", target: "소상공인", categories: [.finance],
                   regions: [.busan], start: makeDate(2025, 8, 10), end: makeDate(2025, 8, 20)),
            source(id: "wrongType", target: "중견기업", categories: [.finance],
                   regions: [.seoul], start: makeDate(2025, 8, 10), end: makeDate(2025, 8, 20)),
            source(id: "closed", target: "서울 소상공인", categories: [.finance],
                   regions: [.seoul], start: makeDate(2025, 7, 1), end: makeDate(2025, 7, 31)),
        ]
        let result = matcher.match(sources, profile: profile, now: now).map(\.id)
        XCTAssertEqual(result, ["hit"])
    }

    // MARK: - 매칭 점수 + 사유

    func testScoreExplicitTargetBeatsOpenToAll() {
        let now = makeDate(2026, 8, 10)
        let m = MoneySourceMatcher()
        let profile = ApplicantProfile(businessTypes: [.soho], region: .seoul, categories: [.finance])
        let explicit = source(id: "e", target: "소상공인", categories: [.finance], regions: [.seoul],
                              start: makeDate(2026, 8, 1), end: makeDate(2026, 8, 13))   // D-3 마감임박
        let open = source(id: "o", target: "누구나 신청 가능", categories: [.finance], regions: [],
                          start: makeDate(2026, 8, 1), end: makeDate(2026, 8, 13))
        XCTAssertGreaterThan(m.score(explicit, profile: profile, now: now).score,
                             m.score(open, profile: profile, now: now).score)
    }

    func testScoreReasonsIncludeTargetAndDeadline() {
        let now = makeDate(2026, 8, 10)
        let m = MoneySourceMatcher()
        let profile = ApplicantProfile(businessTypes: [.soho], region: .seoul, categories: [.finance])
        let src = source(id: "x", target: "서울 소상공인", categories: [.finance], regions: [.seoul],
                         start: makeDate(2026, 8, 1), end: makeDate(2026, 8, 13))  // D-3
        let ms = m.score(src, profile: profile, now: now)
        XCTAssertTrue(ms.reasons.contains(where: { $0.contains("소상공인") }))
        XCTAssertTrue(ms.reasons.contains(where: { $0.contains("마감임박") }))
        XCTAssertGreaterThanOrEqual(ms.score, 80)
    }

    func testMatchScoredSortsByScoreDesc() {
        let now = makeDate(2026, 8, 10)
        let m = MoneySourceMatcher()
        let profile = ApplicantProfile(businessTypes: [.soho], region: .seoul, categories: [.finance])
        let high = source(id: "high", target: "소상공인", categories: [.finance], regions: [.seoul],
                          start: makeDate(2026, 8, 1), end: makeDate(2026, 8, 13))
        let low = source(id: "low", target: "누구나", categories: [], regions: [],
                         start: makeDate(2026, 8, 1), end: makeDate(2026, 8, 30))
        let ranked = m.matchScored([low, high], profile: profile, now: now)
        XCTAssertEqual(ranked.first?.source.id, "high")
    }
}

private struct TestSource: MoneySource {
    let id: String
    let title: String
    let providerName: String
    let summary: String
    let sourceType: MoneySourceType
    let categories: Set<SupportCategory>
    let regions: Set<KoreanRegion>
    let targetAudienceText: String
    let period: ApplicationPeriod
    let detailURL: URL?
    let applyURL: URL?
}
