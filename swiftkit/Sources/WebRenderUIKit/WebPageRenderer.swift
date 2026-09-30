import AppKit
import Foundation
import WebKit

/// 로그인 없는 공개 페이지를 화면 밖 `WKWebView` 로 렌더링해 HTML·본문·링크(·스냅샷)를 얻는다.
///
/// Agent Browser(`browserctl`)가 2026-09-25 폐기돼, JS 로 그리는 페이지를 받을 수단이 없었다
/// (8BFEE0F4 · B 분류: 공고 사이트·SNS 공개 글·가격 페이지·공개 상품 페이지).
///
/// - 세션·쿠키를 남기지 않는다(비영속 데이터 저장소). 로그인·클릭·제출은 하지 않는다.
/// - GUI 앱과 `async main` CLI 모두에서 동작한다. 메인 스레드를 세마포어로 막는 CLI 에서는
///   WebKit 이 진행하지 못하니 부르지 않는다.
public enum WebPageRenderer {
    public enum Snapshot: Sendable, Equatable {
        case none
        case viewport
        /// 문서 전체 높이(상한 `maxSnapshotHeight`).
        case fullPage
    }

    public struct Options: Sendable {
        public static let defaultViewport = CGSize(width: 1280, height: 2000)

        /// 로드 완료까지 기다리는 최대 시간(`URLRequest.timeoutInterval`).
        public var timeout: TimeInterval
        /// 로드 완료 뒤 JS 가 화면을 그리길 기다리는 최대 시간(본문이 멈추면 먼저 끝난다).
        public var settle: TimeInterval
        public var viewport: CGSize
        public var userAgent: String?
        public var snapshot: Snapshot

        public init(
            timeout: TimeInterval = WebRenderTimingConfig.defaultTimeout,
            settle: TimeInterval = WebRenderTimingConfig.defaultSettleLimit,
            viewport: CGSize = Options.defaultViewport,
            userAgent: String? = nil,
            snapshot: Snapshot = .none
        ) {
            self.timeout = timeout
            self.settle = settle
            self.viewport = viewport
            self.userAgent = userAgent
            self.snapshot = snapshot
        }
    }

    public struct Link: Sendable, Equatable, Decodable {
        public let href: String
        public let text: String

        public init(href: String, text: String) {
            self.href = href
            self.text = text
        }
    }

    public struct Page: Sendable {
        public let finalURL: URL
        public let title: String
        public let html: String
        public let text: String
        public let links: [Link]
        public let png: Data?
    }

    public enum Error: Swift.Error, Equatable, CustomStringConvertible {
        case timeout(URL, TimeInterval)
        case http(URL, Int)
        case navigation(String)
        case script(String)

        public var description: String {
            switch self {
            case .timeout(let url, let seconds): return "render timeout \(Int(seconds))s \(url.absoluteString)"
            case .http(let url, let code): return "http \(code) \(url.absoluteString)"
            case .navigation(let why): return "navigation failed: \(why)"
            case .script(let why): return "page script failed: \(why)"
            }
        }
    }

    public static let maxSnapshotHeight: CGFloat = 16_000

    /// 페이지 안에서 돌리는 읽기 전용 스크립트. 결과는 JSON 문자열 하나다.
    static let extractionScript = """
    JSON.stringify({
      title: document.title || "",
      html: document.documentElement ? document.documentElement.outerHTML : "",
      text: document.body ? document.body.innerText : "",
      height: Math.max(document.body ? document.body.scrollHeight : 0,
                       document.documentElement ? document.documentElement.scrollHeight : 0),
      links: Array.from(document.querySelectorAll("a[href]")).slice(0, 3000).map(function (a) {
        return { href: a.href, text: (a.innerText || a.textContent || "").trim().slice(0, 300) };
      })
    })
    """

    struct Extracted: Decodable {
        let title: String
        let html: String
        let text: String
        let height: Double
        let links: [Link]
    }

    static func decode(_ json: String) throws -> Extracted {
        do {
            return try JSONDecoder().decode(Extracted.self, from: Data(json.utf8))
        } catch {
            throw Error.script("unreadable page result: \(error.localizedDescription)")
        }
    }

    @MainActor
    public static func render(_ url: URL, options: Options = Options()) async throws -> Page {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: CGRect(origin: .zero, size: options.viewport), configuration: configuration)
        if let agent = options.userAgent { webView.customUserAgent = agent }
        let loader = PageLoader()
        webView.navigationDelegate = loader
        defer {
            webView.stopLoading()
            webView.navigationDelegate = nil
        }

        try await loader.load(URLRequest(url: url, timeoutInterval: options.timeout), in: webView)
        try await RenderSettlePolling.wait(webView, limit: options.settle)

        let raw: Any?
        do {
            raw = try await webView.evaluateJavaScript(extractionScript)
        } catch {
            throw Error.script(error.localizedDescription)
        }
        guard let json = raw as? String else { throw Error.script("no page result") }
        let extracted = try decode(json)
        let png = try await snapshot(of: webView, mode: options.snapshot, documentHeight: extracted.height)
        return Page(
            finalURL: webView.url ?? url,
            title: extracted.title,
            html: extracted.html,
            text: extracted.text,
            links: extracted.links,
            png: png
        )
    }

    @MainActor
    private static func snapshot(of webView: WKWebView, mode: Snapshot, documentHeight: Double) async throws -> Data? {
        guard mode != .none else { return nil }
        if mode == .fullPage {
            let height = min(max(CGFloat(documentHeight), webView.frame.height), maxSnapshotHeight)
            webView.setFrameSize(CGSize(width: webView.frame.width, height: height))
            try await RenderSettlePolling.pause(WebRenderTimingConfig.resizeSettle)
        }
        let image: NSImage
        do {
            image = try await webView.takeSnapshot(configuration: nil)
        } catch {
            throw Error.script("snapshot failed: \(error.localizedDescription)")
        }
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else { throw Error.script("snapshot encode failed") }
        return png
    }
}
