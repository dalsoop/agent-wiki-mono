import Testing
import Foundation
@testable import OpportunityIntelKit

@Suite("OpportunityIntelKit Tests")
struct OpportunityIntelKitTests {

    @Test("OpportunitySignalParser 한글 정부지원금 및 달러/할인율/코드 파싱")
    func testSignalParser() {
        let title = "[중기부] 2026 AI 바우처 최대 5천만원 지원 (지원율 90%) [코드: BIZ-2026]"
        let body = "총 사업비 5,000만원 한도 내에서 90%를 정부가 지원합니다. 자부담 10% (500만원). 정가 $200/mo 솔루션 도입 가능."

        let parsed = OpportunitySignalParser.parse(title: title, body: body)

        #expect(parsed.pricesOrGrants.contains(where: { $0.contains("5천만원") || $0.contains("5,000만원") }))
        #expect(parsed.pricesOrGrants.contains(where: { $0.contains("$200/mo") }))
        #expect(parsed.discountOrSupportRates.contains(90))
        #expect(parsed.codes.contains("BIZ-2026"))
        #expect(parsed.tags.contains("바우처"))
        #expect(parsed.tags.contains("자부담"))
    }

    @Test("정부사업 특화 패턴 키워드 태그 자동 추출")
    func testGovernmentTagsExtraction() {
        let text = """
        [중소벤처기업부] 2026년 청년창업사관학교 입교생 모집 공고
        민간 매칭펀드 연계 방식 지원.
        인공지능 SaaS 바우처 5천만원 한도 제공.
        민간 자부담금 10% 필수 매칭.
        """
        let tags = OpportunitySignalParser.extractTags(from: text)

        #expect(tags.contains("청년창업"))
        #expect(tags.contains("매칭펀드"))
        #expect(tags.contains("바우처"))
        #expect(tags.contains("자부담"))
    }

    @Test("R&D와 비R&D 태그 상호 간섭 방지 검증")
    func testRDVersusNonRDTags() {
        let nonRDOnly = "2026년도 지역특화 비R&D 패키지 지원사업 안내문"
        let tags1 = OpportunitySignalParser.extractTags(from: nonRDOnly)
        #expect(tags1.contains("비R&D"))
        #expect(!tags1.contains("R&D"))

        let both = "2026 산학연 R&D 연구개발 지원사업 및 후속 비R&D 사업화 연계 공고"
        let tags2 = OpportunitySignalParser.extractTags(from: both)
        #expect(tags2.contains("R&D"))
        #expect(tags2.contains("비R&D"))
        #expect(tags2.contains("사업화"))
    }

    @Test("OpportunityScheduleAudit D-Day 및 3포인트 마일스톤 생성")
    func testScheduleAudit() {
        let firstSeen = "2026-09-01"
        let deadline = "2026-09-20"
        let milestones = OpportunityScheduleAudit.generate3PointMilestones(
            firstSeen: firstSeen,
            deadline: deadline,
            actualValueText: "지원금 5,000만원",
            isGovGrant: true
        )

        #expect(milestones.count == 3)
        #expect(milestones[0].phase == .start)
        #expect(milestones[1].phase == .warning)
        #expect(milestones[1].dateString == "2026-09-17") // 2026-09-20 D-3
        #expect(milestones[2].phase == .completion)
        #expect(milestones[2].dateString == "2026-09-20")
    }

    @Test("MutedIntelPreferences 제공자 필터링")
    func testMutedPreferences() {
        let prefs = MutedIntelPreferences(mutedProviders: ["특정기관"])
        let item1 = OpportunityIntelItem(
            id: "1",
            provider: "중소벤처기업부",
            title: "공고",
            summary: "요약",
            url: "https://example.com",
            category: "grants"
        )
        let item2 = OpportunityIntelItem(
            id: "2",
            provider: "특정기관",
            title: "스팸 공고",
            summary: "요약",
            url: "https://example.com/spam",
            category: "grants"
        )

        #expect(!prefs.isMuted(item: item1))
        #expect(prefs.isMuted(item: item2))
    }

    // MARK: - OpportunityDedupEngine 단위 테스트

    @Test("OpportunityDedupEngine 동일 기관 및 유사 제목 공고 중복제거 및 병합")
    func testDedupSameProviderAndSimilarTitle() {
        let itemA = OpportunityIntelItem(
            id: "gov:2026:ai-v1",
            provider: "중소벤처기업부",
            canonical: "mss",
            title: "[공고] 2026년 인공지능 AI 바우처 지원사업 공고",
            summary: "초기 공고 안내",
            url: "https://k-startup.go.kr/notice/view?id=101",
            category: "gov-grants",
            standardValue: "5,000만원",
            actualValue: "정부지원 4,500만원",
            discountOrSupportRate: 80,
            deadline: "2026-09-15",
            firstSeen: "2026-08-01",
            lastSeen: "2026-08-10",
            tags: ["바우처"]
        )

        let itemB = OpportunityIntelItem(
            id: "gov:2026:ai-v2",
            provider: "중기부",
            canonical: "mss",
            title: "2026년 인공지능 AI 바우처 지원사업 모집안내 (접수연장)",
            summary: "접수 마감일이 연장되었습니다. 상세 지침 확인 요망.",
            url: "https://k-startup.go.kr/notice/view?id=101&ref=alert",
            category: "gov-grants",
            standardValue: "1억원",
            actualValue: "정부지원 1억원 (최대)",
            discountOrSupportRate: 90,
            deadline: "2026-09-30",
            firstSeen: "2026-08-05",
            lastSeen: "2026-09-11",
            tags: ["자부담"]
        )

        let deduped = OpportunityDedupEngine.deduplicate([itemA, itemB])

        #expect(deduped.count == 1)
        let merged = deduped[0]

        // 1. 최신 마감일 보존 (2026-09-15 vs 2026-09-30 -> 2026-09-30)
        #expect(merged.deadline == "2026-09-30")

        // 2. 최고 지원금 및 지원율 보존 (4,500만원 vs 1억원 -> 1억원 / 90%)
        #expect(merged.actualValue?.contains("1억원") == true)
        #expect(merged.discountOrSupportRate == 90)

        // 3. 최초 발견일 min, 최종 확인일 max 보존
        #expect(merged.firstSeen == "2026-08-01")
        #expect(merged.lastSeen == "2026-09-11")

        // 4. 태그 통합 보존
        #expect(merged.tags.contains("바우처"))
        #expect(merged.tags.contains("자부담"))
    }

    @Test("OpportunityDedupEngine 동일 URL(추적 파라미터 차이) 중복제거")
    func testDedupSameURLDifferentParams() {
        let item1 = OpportunityIntelItem(
            id: "saas:1",
            provider: "GitHub",
            title: "GitHub Copilot 학생 할인 프로모션",
            summary: "학생 인증 시 무료",
            url: "https://github.com/education?utm_source=twitter&utm_medium=social",
            category: "saas-deals"
        )
        let item2 = OpportunityIntelItem(
            id: "saas:2",
            provider: "GitHub",
            title: "GitHub Copilot 무료 플랜",
            summary: "학생 전용 혜택",
            url: "https://github.com/education?utm_source=newsletter",
            category: "saas-deals"
        )

        let deduped = OpportunityDedupEngine.deduplicate([item1, item2])
        #expect(deduped.count == 1)
    }

    @Test("OpportunityDedupEngine 상이한 기관의 유사 제목 공고는 분리 보존")
    func testDedupDifferentProvidersNotMerged() {
        let item1 = OpportunityIntelItem(
            id: "mss:1",
            provider: "중소벤처기업부",
            title: "2026년 인공지능 혁신 인재양성 사업",
            summary: "중기부 주관 사업",
            url: "https://k-startup.go.kr/notice/1",
            category: "gov-grants"
        )
        let item2 = OpportunityIntelItem(
            id: "msit:1",
            provider: "과학기술정보통신부",
            title: "2026년 인공지능 혁신 인재양성 사업",
            summary: "과기정통부 주관 사업",
            url: "https://msit.go.kr/notice/1",
            category: "gov-grants"
        )

        let deduped = OpportunityDedupEngine.deduplicate([item1, item2])
        #expect(deduped.count == 2)
    }
}
