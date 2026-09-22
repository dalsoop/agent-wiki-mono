import Foundation
import HTTPClientKit

// 공개 웹 페이지 비동기 fetch — HTTPClientKit(주입 가능, 테스트 목킹 가능) 위에
// 브라우저형 User-Agent·Accept 를 얹는다(봇 차단 회피). 정적/서버렌더 페이지에 적합.
// JS 렌더링 전용 사이트는 WebFetch 만으로는 안 되고 browserctl(AgentBrowser) 폴백이 필요하다.

public enum WebFetch {
    public enum Error: Swift.Error, CustomStringConvertible {
        case http(Int)
        case transport(String)
        case empty
        public var description: String {
            switch self {
            case .http(let c): return "http \(c)"
            case .transport(let s): return s
            case .empty: return "empty body"
            }
        }
    }

    public static let defaultUA =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"

    public static let defaultTimeout: TimeInterval = 30

    /// 안티봇(Cloudflare, WAF) 차단을 우회하기 위한 표준 macOS Chrome 헤더 세트
    public static let standardBrowserHeaders: [String: String] = [
        "User-Agent": defaultUA,
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8",
        "Accept-Language": "ko-KR,ko;q=0.9,en-US;q=0.8,en;q=0.7",
        "sec-ch-ua": "\"Not/A)Brand\";v=\"8\", \"Chromium\";v=\"126\", \"Google Chrome\";v=\"126\"",
        "sec-ch-ua-mobile": "?0",
        "sec-ch-ua-platform": "\"macOS\"",
        "Sec-Fetch-Dest": "document",
        "Sec-Fetch-Mode": "navigate",
        "Sec-Fetch-Site": "none",
        "Sec-Fetch-User": "?1",
        "Upgrade-Insecure-Requests": "1"
    ]

    /// GET 으로 본문 데이터를 가져온다. 상태 200..<400 만 성공.
    public static func getData(
        _ url: URL,
        timeout: TimeInterval = defaultTimeout,
        extraHeaders: [String: String] = [:],
        client: any HTTPClient = URLSessionHTTPClient()
    ) async throws -> Data {
        var headers = standardBrowserHeaders
        for (k, v) in extraHeaders { headers[k] = v }
        let (status, data) = try await client.send(method: "GET", url: url, headers: headers, body: nil)
        guard (200..<400).contains(status) else { throw Error.http(status) }
        guard !data.isEmpty else { throw Error.empty }
        return data
    }

    /// GET 으로 본문 문자열을 가져온다. 상태 200..<400 만 성공.
    public static func get(
        _ url: URL,
        timeout: TimeInterval = defaultTimeout,
        extraHeaders: [String: String] = [:],
        client: any HTTPClient = URLSessionHTTPClient()
    ) async throws -> String {
        let data = try await getData(url, timeout: timeout, extraHeaders: extraHeaders, client: client)
        guard let text = String(data: data, encoding: .utf8), !text.isEmpty else { throw Error.empty }
        return text
    }
}
