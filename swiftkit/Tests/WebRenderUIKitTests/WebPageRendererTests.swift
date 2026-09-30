import XCTest
@testable import WebRenderUIKit

final class WebPageRendererTests: XCTestCase {
    func testDecodesThePageResult() throws {
        let json = #"{"title":"T","html":"<html></html>","text":"body","height":1200,"links":[{"href":"https://a.example/x","text":"X"}]}"#
        let page = try WebPageRenderer.decode(json)
        XCTAssertEqual(page.title, "T")
        XCTAssertEqual(page.text, "body")
        XCTAssertEqual(page.links, [WebPageRenderer.Link(href: "https://a.example/x", text: "X")])
    }

    func testUnreadableResultIsAScriptError() {
        XCTAssertThrowsError(try WebPageRenderer.decode("not json")) { error in
            guard case WebPageRenderer.Error.script = error else { return XCTFail("\(error)") }
        }
    }

    /// 빈 본문·로딩 중·미완료 문서는 "다 그렸다"로 보지 않는다(로드 직후 다시 이동하는 사이트).
    func testSettleNeedsACompleteNonEmptyUnchangedBody() {
        let full = RenderSettlePolling.Sample.parse("complete|1200")
        XCTAssertEqual(full, RenderSettlePolling.Sample(complete: true, length: 1200))
        XCTAssertTrue(RenderSettlePolling.isSettled(previous: full, current: full, loading: false))
        XCTAssertFalse(RenderSettlePolling.isSettled(previous: full, current: full, loading: true))
        let empty = RenderSettlePolling.Sample.parse("complete|0")
        XCTAssertFalse(RenderSettlePolling.isSettled(previous: empty, current: empty, loading: false))
        let loading = RenderSettlePolling.Sample.parse("interactive|1200")
        XCTAssertFalse(RenderSettlePolling.isSettled(previous: loading, current: loading, loading: false))
        XCTAssertFalse(RenderSettlePolling.isSettled(previous: full, current: .init(complete: true, length: 1300), loading: false))
        XCTAssertNil(RenderSettlePolling.Sample.parse("garbage"))
    }

    /// 스크립트가 그린 본문·링크를 읽는다 — JS 렌더링 페이지를 받는 것이 이 킷의 목적이다.
    @MainActor
    func testReadsContentThatJavaScriptRendered() async throws {
        let html = """
        <html><head><title>Rendered</title></head><body><div id="root"></div>
        <script>document.getElementById('root').innerHTML =
          '<p>공고 목록</p><a href="https://example.com/notice/1">첫 공고</a>';</script>
        </body></html>
        """
        let encoded = try XCTUnwrap(html.addingPercentEncoding(withAllowedCharacters: .alphanumerics))
        let url = try XCTUnwrap(URL(string: "data:text/html;charset=utf-8,\(encoded)"))

        let page = try await WebPageRenderer.render(url, options: .init(timeout: 20, settle: 0.2, snapshot: .viewport))

        XCTAssertEqual(page.title, "Rendered")
        XCTAssertTrue(page.text.contains("공고 목록"), page.text)
        XCTAssertEqual(page.links.first?.href, "https://example.com/notice/1")
        XCTAssertEqual(page.links.first?.text, "첫 공고")
        XCTAssertFalse(page.png?.isEmpty ?? true)
    }
}
