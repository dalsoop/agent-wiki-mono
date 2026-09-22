import Foundation

// MARK: - Claude Code OAuth 토큰 갱신
//
// blob 에 저장된 OAuth accessToken 은 짧게 만료된다(수 시간). 비활성 계정의 한도를 조회하려면
// refreshToken 으로 새 accessToken 을 발급받아야 한다. 엔드포인트/클라이언트ID 는 Claude Code
// OAuth 공개값이다. 갱신 시 refreshToken 도 회전될 수 있으므로 호출부는 새 값을 blob 에 되써야
// 다음 조회가 이어진다.

public struct ClaudeOAuthToken: Sendable, Equatable {
    public let accessToken: String
    public let refreshToken: String?
    public let expiresAt: Date?

    public init(accessToken: String, refreshToken: String?, expiresAt: Date?) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }
}

public enum ClaudeOAuthRefreshError: Error, CustomStringConvertible, Sendable {
    case badResponse(String)
    case invalidGrant

    public var description: String {
        switch self {
        case .invalidGrant: return "refresh token invalid/rotated — 재로그인 필요"
        case .badResponse(let s): return "refresh failed: \(s)"
        }
    }
}

public enum ClaudeOAuthRefresher {
    private final class ResponseBox: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Result<(Data, URLResponse), Error>?

        func store(_ result: Result<(Data, URLResponse), Error>) {
            lock.lock()
            value = result
            lock.unlock()
        }

        func load() -> Result<(Data, URLResponse), Error>? {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
    }

    /// Claude Code OAuth 공개 client id.
    public static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    // 현행 토큰 엔드포인트(구 console.anthropic.com 은 404). platform.claude.com 이 정본.
    static let tokenURL = URL(string: "https://platform.claude.com/v1/oauth/token")!

    public static func refresh(refreshToken: String) throws -> ClaudeOAuthToken {
        var req = URLRequest(url: tokenURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // 일부 프런트(CF)에서 봇 차단을 피하려 UA 를 명시한다.
        req.setValue("claude-cli/1.0 (external, cli)", forHTTPHeaderField: "User-Agent")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID,
        ])
        req.timeoutInterval = 20

        let (data, resp) = try sendSynchronously(req)
        guard let http = resp as? HTTPURLResponse else {
            throw ClaudeOAuthRefreshError.badResponse("no HTTP response")
        }
        return try parseResponse(data: data, statusCode: http.statusCode)
    }

    /// macOS 26의 CLI 프로세스에서 async URLSession refresh가 Swift task allocator
    /// EXC_BAD_ACCESS를 일으킨 회귀를 피한다. 전용 dataTask를 최대 25초만 기다린다.
    private static func sendSynchronously(_ request: URLRequest) throws -> (Data, URLResponse) {
        let semaphore = DispatchSemaphore(value: 0)
        let box = ResponseBox()
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                box.store(.failure(error))
            } else if let data, let response {
                box.store(.success((data, response)))
            } else {
                box.store(.failure(ClaudeOAuthRefreshError.badResponse("no HTTP response")))
            }
            semaphore.signal()
        }
        task.resume()
        guard semaphore.wait(timeout: .now() + 25) == .success else {
            task.cancel()
            throw URLError(.timedOut)
        }
        guard let result = box.load() else {
            throw ClaudeOAuthRefreshError.badResponse("missing response")
        }
        return try result.get()
    }

    static func parseResponse(data: Data, statusCode: Int) throws -> ClaudeOAuthToken {
        guard statusCode == 200 else {
            let body = String(decoding: data, as: UTF8.self)
            if body.contains("invalid_grant") { throw ClaudeOAuthRefreshError.invalidGrant }
            throw ClaudeOAuthRefreshError.badResponse("HTTP \(statusCode): \(body.prefix(200))")
        }
        guard let obj = ClaudeJSON.object(from: data),
              let access = obj["access_token"] as? String, !access.isEmpty else {
            throw ClaudeOAuthRefreshError.badResponse("missing access_token")
        }
        let newRefresh = obj["refresh_token"] as? String
        let expiresAt = (obj["expires_in"] as? Double).map { Date().addingTimeInterval($0) }
        return ClaudeOAuthToken(accessToken: access, refreshToken: newRefresh, expiresAt: expiresAt)
    }
}
