import Foundation
import WebKit

/// 한 번의 로드를 기다리는 내비게이션 대리자. 완료·실패·HTTP 오류 중 먼저 온 하나로 끝낸다.
/// 시간 초과는 `URLRequest.timeoutInterval` 이 실패로 알려 준다.
@MainActor
final class PageLoader: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?
    private var url: URL?
    private var timeout: TimeInterval = 0

    func load(_ request: URLRequest, in webView: WKWebView) async throws {
        url = request.url
        timeout = request.timeoutInterval
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.continuation = continuation
            webView.load(request)
        }
    }

    private func finish(_ result: Result<Void, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
        finish(.success(()))
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation?, withError error: Error) {
        finish(.failure(WebPageRenderer.Error.navigation(error.localizedDescription)))
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation?,
        withError error: Error
    ) {
        finish(.failure(Self.classify(error, url: url, timeout: timeout)))
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void
    ) {
        if navigationResponse.isForMainFrame,
           let http = navigationResponse.response as? HTTPURLResponse,
           http.statusCode >= 400 {
            decisionHandler(.cancel)
            finish(.failure(WebPageRenderer.Error.http(http.url ?? url ?? URL(fileURLWithPath: "/"), http.statusCode)))
            return
        }
        decisionHandler(.allow)
    }

    /// 요청 시간 초과는 따로 알린다 — 호출자가 재시도할지 판단한다.
    static func classify(_ error: Error, url: URL?, timeout: TimeInterval) -> WebPageRenderer.Error {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain, ns.code == NSURLErrorTimedOut, let url {
            return .timeout(url, timeout)
        }
        return .navigation(error.localizedDescription)
    }
}
