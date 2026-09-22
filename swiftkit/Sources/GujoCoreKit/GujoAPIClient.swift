import Foundation
import LocalizationKit

public struct APIError: Error, LocalizedError, Sendable {
    public let status: Int
    public let body: String
    public init(status: Int, body: String) { self.status = status; self.body = body }
    public var errorDescription: String? {
        let snippet = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let short: String = {
            if snippet.isEmpty { return "" }
            return snippet.count > GujoAPIClient.Timing.errorBodyLimit
                ? String(snippet.prefix(GujoAPIClient.Timing.errorBodyLimit)) + "…"
                : snippet
        }()
        switch status {
        case GujoAPIClient.Timing.unauthorizedStatus, GujoAPIClient.Timing.forbiddenStatus:
            return CLILocalization.format("GujoAPIClient.return", String(status)) + (short.isEmpty ? "" : ": \(short)")
        case GujoAPIClient.Timing.notFoundStatus:
            return CLILocalization.string("GujoAPIClient.return-2") + (short.isEmpty ? "" : ": \(short)")
        case 502, 503, 504:
            return CLILocalization.format("GujoAPIClient.return-3", String(status)) + (short.isEmpty ? "" : ": \(short)")
        default:
            if short.isEmpty { return CLILocalization.format("GujoAPIClient.return-4", String(status)) }
            return CLILocalization.format("GujoAPIClient.return-5", String(status), short)
        }
    }
}

public final class GujoAPIClient: GujoAPI {
    /// 요청마다 API key 를 새로 받는다. 클라이언트는 key 를 **보관하지 않는다** (#28 D8) —
    /// 값은 `request(_:)` 스코프에서만 살아 있다.
    public typealias APIKeyProvider = @Sendable () async throws -> String

    private let baseURL: URL
    private let apiKeyProvider: APIKeyProvider
    private let session: URLSession
    enum Timing {
        static let requestTimeout: TimeInterval = 45
        static let retryBackoffNanoseconds = 150_000_000
        static let downloadBackoffNanoseconds = 200_000_000
        static let errorBodyLimit = 200
        static let defaultMaxAttempts = 3
        static let successStatusCodes = 200..<300
        static let unauthorizedStatus = 401
        static let forbiddenStatus = 403
        static let notFoundStatus = 404
        static let gatewayTimeoutStatus = 504
    }

    /// 일시 장애(502/503/504)·타임아웃 재시도 횟수 (첫 시도 포함 총 1+retries).
    private let maxAttempts: Int

    public init(
        baseURL: URL,
        session: URLSession = .shared,
        maxAttempts: Int = 3,
        apiKey: @escaping APIKeyProvider
    ) {
        self.baseURL = baseURL
        self.apiKeyProvider = apiKey
        self.session = session
        self.maxAttempts = max(1, maxAttempts)
    }

    private func request(_ path: String) async throws -> URLRequest {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.setValue("Bearer \(try await apiKeyProvider())", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        // 라이브러리 목록은 커질 수 있음 — 클라이언트 타임아웃 여유.
        req.timeoutInterval = Timing.requestTimeout
        return req
    }

    private func isRetryable(status: Int) -> Bool {
        status == 502 || status == 503 || status == 504
    }

    private func isRetryable(error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorTimedOut, NSURLErrorNetworkConnectionLost,
                 NSURLErrorCannotConnectToHost, NSURLErrorDNSLookupFailed,
                 NSURLErrorNotConnectedToInternet:
                return true
            default:
                return false
            }
        }
        return false
    }

    private func data(_ path: String) async throws -> Data {
        var lastError: Error?
        for attempt in 1...maxAttempts {
            do {
                let (data, response) = try await session.data(for: try await request(path))
                guard let http = response as? HTTPURLResponse else {
                    throw APIError(status: -1, body: "응답이 HTTP 가 아닙니다")
                }
                if Timing.successStatusCodes.contains(http.statusCode) {
                    return data
                }
                let err = APIError(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
                if isRetryable(status: http.statusCode), attempt < maxAttempts {
                    lastError = err
                    let ns: UInt64 = UInt64(Timing.retryBackoffNanoseconds * attempt)
                    try await Task.sleep(nanoseconds: ns)
                    continue
                }
                throw err
            } catch let e as APIError {
                throw e
            } catch {
                if isRetryable(error: error), attempt < maxAttempts {
                    lastError = error
                    let ns: UInt64 = UInt64(Timing.retryBackoffNanoseconds * attempt)
                    try await Task.sleep(nanoseconds: ns)
                    continue
                }
                // URLError 등을 읽기 쉬운 메시지로.
                if let urlErr = error as? URLError, urlErr.code == .timedOut {
                    throw APIError(status: Timing.gatewayTimeoutStatus, body: "요청 시간 초과 — 네트워크/서버 부하 가능")
                }
                throw error
            }
        }
        throw lastError ?? APIError(status: -1, body: "재시도 실패")
    }

    public func library() async throws -> [LibraryItem] {
        let data = try await data("api/library")
        return try JSONDecoder().decode(LibraryResponse.self, from: data).items
    }

    public func productDetail(id: Int) async throws -> ProductDetailResponse {
        let data = try await data("api/products/\(id)/detail")
        return try JSONDecoder().decode(ProductDetailResponse.self, from: data)
    }

    public func contentAsset(id: Int, path: String) async throws -> Data {
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        return try await data("api/products/\(id)/content-assets/\(encoded)")
    }

    public func productContentCss() async throws -> String {
        String(decoding: try await data("api/product-content.css"), as: UTF8.self)
    }

    public func downloadBundle(id: Int) async throws -> URL {
        var lastError: Error?
        for attempt in 1...maxAttempts {
            do {
                let (tmp, response) = try await session.download(for: try await request("api/products/\(id)/bundle"))
                guard let http = response as? HTTPURLResponse else {
                    throw APIError(status: -1, body: "번들 응답이 HTTP 가 아닙니다")
                }
                if Timing.successStatusCodes.contains(http.statusCode) {
                    let dest = tmp.deletingLastPathComponent().appendingPathComponent("gujo-bundle-\(id)-\(UUID().uuidString).zip")
                    try FileManager.default.moveItem(at: tmp, to: dest)
                    return dest
                }
                let err = APIError(status: http.statusCode, body: "")
                if isRetryable(status: http.statusCode), attempt < maxAttempts {
                    lastError = err
                    try await Task.sleep(nanoseconds: UInt64(Timing.downloadBackoffNanoseconds * attempt))
                    continue
                }
                throw err
            } catch let e as APIError {
                throw e
            } catch {
                if isRetryable(error: error), attempt < maxAttempts {
                    lastError = error
                    try await Task.sleep(nanoseconds: UInt64(Timing.downloadBackoffNanoseconds * attempt))
                    continue
                }
                throw error
            }
        }
        throw lastError ?? APIError(status: -1, body: "번들 다운로드 재시도 실패")
    }
}
