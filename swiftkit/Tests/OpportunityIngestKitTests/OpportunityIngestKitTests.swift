import Testing
import Foundation
@testable import OpportunityIngestKit
import OpportunityIntelKit

@Suite("OpportunityIngestKit Tests")
struct OpportunityIngestKitTests {

    @Test("OpportunityURLResolver 상대경로 안전 결합")
    func testURLResolver() throws {
        let base = try #require(URL(string: "https://k-startup.go.kr/board/list.do"))

        let rel1 = "/notice/view.do?id=123&utm_source=fb"
        let resolved1 = OpportunityURLResolver.resolve(relative: rel1, baseURL: base)
        #expect(resolved1 == "https://k-startup.go.kr/notice/view.do?id=123")

        let rel2 = "detail.do?id=456&promo=BIZ2026"
        let resolved2 = OpportunityURLResolver.resolve(relative: rel2, baseURL: base)
        #expect(resolved2 == "https://k-startup.go.kr/board/detail.do?id=456&promo=BIZ2026")

        let host = OpportunityURLResolver.extractHost(from: "https://www.anthropic.com/pricing")
        #expect(host == "anthropic.com")
    }

    @Test("OpportunityFeedScanner RSS 2.0 피드 파싱 및 신호 자동 추출")
    func testRSS2Parsing() {
        let rssXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
          <channel>
            <title>K-Startup 지원사업 공고</title>
            <link>https://www.k-startup.go.kr</link>
            <description>중소벤처기업부 공식 창업지원 공고 피드</description>
            <item>
              <title>[중기부] 2026 AI 바우처 최대 5천만원 지원 (지원율 90%) [코드: BIZ-2026]</title>
              <link>https://www.k-startup.go.kr/notice/view.do?id=101</link>
              <guid>kstartup-101</guid>
              <pubDate>Mon, 01 Sep 2026 09:00:00 +0900</pubDate>
              <category>R&amp;D/AI</category>
              <description><![CDATA[총 사업비 5,000만원 한도 내에서 90%를 정부가 지원합니다. 마감일: 2026-10-31]]></description>
            </item>
          </channel>
        </rss>
        """

        let items = OpportunityFeedScanner.scan(xmlString: rssXML)
        #expect(items.count == 1)

        let item = items[0]
        #expect(item.title.contains("AI 바우처"))
        #expect(item.provider == "K-Startup 지원사업 공고")
        #expect(item.url == "https://www.k-startup.go.kr/notice/view.do?id=101")
        #expect(item.category == "R&D/AI")
        #expect(item.actualValue?.contains("5천만원") == true || item.actualValue?.contains("5,000만원") == true)
        #expect(item.discountOrSupportRate == 90)
        #expect(item.opportunityCode == "BIZ-2026")
        #expect(item.deadline == "2026-10-31")
        #expect(item.firstSeen == "2026-09-01")
        #expect(item.liveness == .alive)
    }

    @Test("OpportunityFeedScanner Atom 피드 파싱")
    func testAtomParsing() {
        let atomXML = """
        <?xml version="1.0" encoding="utf-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <title>글로벌 SaaS 딜 레이더</title>
          <entry>
            <title>Claude Code Pro 연간 플랜 50% 특별 할인 [코드: PROMO-50]</title>
            <link href="https://anthropic.com/pricing?coupon=PROMO-50" rel="alternate"/>
            <id>claude-deal-2026</id>
            <updated>2026-09-05T12:00:00Z</updated>
            <category term="subscription-deals"/>
            <summary>정가 $200/mo 솔루션을 $20/mo 가격으로 50% 할인 제공. 접수마감: 2026-12-31</summary>
          </entry>
        </feed>
        """

        let items = OpportunityFeedScanner.scan(xmlString: atomXML)
        #expect(items.count == 1)

        let item = items[0]
        #expect(item.title.contains("Claude Code Pro"))
        #expect(item.category == "subscription-deals")
        #expect(item.opportunityCode == "PROMO-50")
        #expect(item.discountOrSupportRate == 50)
        #expect(item.deadline == "2026-12-31")
        #expect(item.liveness == .alive)
    }

    @Test("OpportunityHTMLTableParser 정형 테이블 게시판 파싱")
    func testHTMLTableParsing() throws {
        let tableHTML = """
        <table class="board_table">
          <thead>
            <tr>
              <th>번호</th>
              <th>분류</th>
              <th>공고명</th>
              <th>소관기관</th>
              <th>마감일</th>
              <th>진행상태</th>
            </tr>
          </thead>
          <tbody>
            <tr>
              <td>1</td>
              <td>창업지원</td>
              <td><a href="/biz/view.do?id=999">2026 글로벌 스타트업 패키지 지원사업 공고 (최대 1억원)</a></td>
              <td>창업진흥원</td>
              <td>2026-11-30</td>
              <td><span class="badge">접수중</span></td>
            </tr>
            <tr>
              <td>2</td>
              <td>R&amp;D</td>
              <td><a href="/biz/view.do?id=888">2026 중소기업 기술개발 지원사업 공고</a></td>
              <td>중소벤처기업부</td>
              <td>2026-08-01</td>
              <td><span class="badge">접수마감</span></td>
            </tr>
          </tbody>
        </table>
        """

        let base = try #require(URL(string: "https://www.k-startup.go.kr/board/list.do"))
        let items = OpportunityHTMLTableParser.parse(html: tableHTML, baseURL: base)

        #expect(items.count == 2)

        let activeItem = items[0]
        #expect(activeItem.title.contains("글로벌 스타트업 패키지"))
        #expect(activeItem.url == "https://www.k-startup.go.kr/biz/view.do?id=999")
        #expect(activeItem.provider == "창업진흥원")
        #expect(activeItem.category == "창업지원")
        #expect(activeItem.deadline == "2026-11-30")
        #expect(activeItem.actualValue?.contains("1억원") == true)
        #expect(activeItem.liveness == .alive)

        let expiredItem = items[1]
        #expect(expiredItem.title.contains("기술개발 지원사업"))
        #expect(expiredItem.provider == "중소벤처기업부")
        #expect(expiredItem.deadline == "2026-08-01")
        #expect(expiredItem.liveness == .expired)
    }

    @Test("OpportunityHTMLTableParser 비정형 Li 리스트 게시판 파싱")
    func testHTMLListParsing() throws {
        let cls = "class"
        let listHTML = """
        <ul \(cls)="notice_list">
          <li \(cls)="item">
            <span \(cls)="badge">모집중</span>
            <a href="/deals/view?id=77">OpenAI API 엔터프라이즈 바우처 지원 [코드: AI-2026]</a>
            <span \(cls)="agency">중소벤처기업진흥공단</span>
            <span \(cls)="period">신청기한: 2026.10.15</span>
          </li>
        </ul>
        """

        let base = try #require(URL(string: "https://www.semas.or.kr/board/list"))
        let items = OpportunityHTMLTableParser.parse(html: listHTML, baseURL: base)

        #expect(items.count == 1)
        let item = items[0]
        #expect(item.title.contains("OpenAI API 엔터프라이즈 바우처"))
        #expect(item.url == "https://www.semas.or.kr/deals/view?id=77")
        #expect(item.provider == "중소벤처기업진흥공단")
        #expect(item.opportunityCode == "AI-2026")
        #expect(item.deadline == "2026-10-15")
        #expect(item.liveness == .alive)
    }
}
