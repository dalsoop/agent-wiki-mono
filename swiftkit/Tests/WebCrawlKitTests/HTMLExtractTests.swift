import XCTest
@testable import WebCrawlKit

/// HTML 파싱 헬퍼 고정 — 셀/링크/엔티티/인클로징 범위.
final class HTMLExtractTests: XCTestCase {

    func testCellsParseAndDecodeEntities() {
        let row = "<tr><td>1</td><td>금융</td><td class=\"txt_l\"><a href=\"/x\">A &amp; B</a></td></tr>"
        let cells = HTMLExtract.cells(in: row)
        XCTAssertEqual(cells.count, 3)
        XCTAssertEqual(cells[1], "금융")
        XCTAssertEqual(cells[2], "A & B", "&amp; 가 & 로 디코드돼야")
    }

    func testLinksResolveRelative() {
        let html = #"<a href="/p/1?pblancId=PBLN_1">제목</a><a href="https://o.kr/x">외부</a>"#
        let links = HTMLExtract.links(in: html, base: "https://www.bizinfo.go.kr/")
        XCTAssertEqual(links.count, 2)
        XCTAssertEqual(links[0].href, "https://www.bizinfo.go.kr/p/1?pblancId=PBLN_1")
        XCTAssertEqual(links[0].text, "제목")
        XCTAssertEqual(links[1].href, "https://o.kr/x")
    }

    func testFirstMatch() {
        let s = "abc 2026-08-07 ~ 2026-08-12 zzz"
        XCTAssertEqual(HTMLExtract.firstMatch(#"(\d{4}-\d{2}-\d{2}\s*~\s*\d{4}-\d{2}-\d{2})"#, in: s),
                       "2026-08-07 ~ 2026-08-12")
    }

    func testEnclosingRange() {
        let html = "<table><tr><td>x</td></tr><tr><td id=\"hit\">Y</td></tr><tr><td>z</td></tr></table>" as NSString
        let hit = html.range(of: "id=\"hit\"")
        let r = HTMLExtract.enclosingRange(containing: hit.location, in: html)!
        let row = html.substring(with: r)
        XCTAssertTrue(row.contains("Y"))
        XCTAssertFalse(row.contains(">z<"))
    }

    func testBotBlockedHosts() {
        XCTAssertTrue(BotBlockedHosts.isKnownBotWalled("https://x.com/foo"))
        XCTAssertTrue(BotBlockedHosts.isKnownBotWalled("https://www.instagram.com/"))
        XCTAssertFalse(BotBlockedHosts.isKnownBotWalled("https://www.bizinfo.go.kr/"))
    }

    func testEmbeddedBaseHrefResolution() {
        let html = """
        <html>
        <head><base href="https://example.com/sub/"></head>
        <body>
            <a href="pricing">Pricing</a>
            <a href="/deals">Deals</a>
            <a href="https://other.com/promo">External</a>
        </body>
        </html>
        """
        let links = HTMLExtract.links(in: html)
        XCTAssertEqual(links.count, 3)
        XCTAssertEqual(links[0].href, "https://example.com/sub/pricing")
        XCTAssertEqual(links[1].href, "https://example.com/deals")
        XCTAssertEqual(links[2].href, "https://other.com/promo")
    }

    func testOfferURLNormalizerPreservesDealParamsAndStripsTracking() {
        let dirty = "https://EXAMPLE.com/pricing?utm_source=twitter&coupon=SAVE50&fbclid=xyz123&plan=pro"
        let clean = OfferURLNormalizer.normalize(dirty)
        XCTAssertEqual(clean, "https://example.com/pricing?coupon=SAVE50&plan=pro")
        XCTAssertFalse(clean.contains("utm_source"))
        XCTAssertFalse(clean.contains("fbclid"))

        let promo = OfferURLNormalizer.extractPromoCode(from: dirty)
        XCTAssertEqual(promo, "SAVE50")
    }

    func testStandardBrowserHeadersContainChromeUAAndSecCh() {
        let headers = WebFetch.standardBrowserHeaders
        XCTAssertTrue(headers["User-Agent"]?.contains("Chrome") == true)
        XCTAssertFalse(headers["User-Agent"]?.contains("SwiftAppMono") == true)
        XCTAssertEqual(headers["Sec-Fetch-Mode"], "navigate")
    }
}
