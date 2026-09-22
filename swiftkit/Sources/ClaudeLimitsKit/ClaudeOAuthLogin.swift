#if canImport(CryptoKit)
import CryptoKit
import Foundation

// MARK: - Claude Code OAuth 로그인 (인앱, PKCE)
//
// 외부 `claude` 로그인에 의존하지 않고 앱이 직접 OAuth 를 수행한다.
// 흐름: begin() 으로 PKCE + authorize URL 생성 → 브라우저에서 로그인/승인 →
// claude.ai 가 보여주는 `code#state` 를 사용자가 붙여넣기 → complete() 가 토큰 교환 →
// Claude Code 자격증명 blob(`{claudeAiOauth, organizationUuid}`) 을 만든다.
//
// client_id·엔드포인트는 Claude Code OAuth 공개값(ClaudeOAuthRefresher 와 공유).

public struct ClaudePendingLogin: Sendable, Equatable {
    public let authorizeURL: URL
    public let verifier: String
    public let state: String
}

/// 로그인 결과 = 계정 저장에 필요한 모든 것.
public struct ClaudeLoginResult: Sendable, Equatable {
    public let blob: Data          // {"claudeAiOauth": {...}, "organizationUuid": ...}
    public let organizationUuid: String?
    public let email: String?

    public init(blob: Data, organizationUuid: String?, email: String?) {
        self.blob = blob
        self.organizationUuid = organizationUuid
        self.email = email
    }
}

public enum ClaudeOAuthLoginError: Error, CustomStringConvertible, Sendable, Equatable {
    case badResponse(String)
    case stateMismatch

    public var description: String {
        switch self {
        case .stateMismatch: return "state 불일치 — 붙여넣은 코드가 이 로그인 요청과 다릅니다"
        case .badResponse(let s): return "로그인 실패: \(s)"
        }
    }
}

public enum ClaudeOAuthLogin {
    // 현행 Claude Code OAuth 엔드포인트(구 claude.ai/console.anthropic.com 은 폐기).
    // `claude setup-token` 이 실제로 여는 값과 일치.
    static let authorizeBase = "https://claude.com/cai/oauth/authorize"
    static let redirectURI = "https://platform.claude.com/oauth/code/callback"
    static let scope = "org:create_api_key user:profile user:inference"

    /// PKCE + authorize URL 생성. 브라우저로 열 URL 과, complete 에 넘길 verifier/state 를 돌려준다.
    public static func begin() -> ClaudePendingLogin {
        let verifier = randomURLSafe(64)
        let challenge = base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        let state = randomURLSafe(32)
        var comp = URLComponents(string: authorizeBase)!
        comp.queryItems = [
            .init(name: "code", value: "true"),
            .init(name: "client_id", value: ClaudeOAuthRefresher.clientID),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "scope", value: scope),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state),
        ]
        return ClaudePendingLogin(authorizeURL: comp.url!, verifier: verifier, state: state)
    }

    /// 붙여넣은 `code#state`(또는 code) 를 토큰으로 교환하고 blob 을 만든다.
    public static func complete(pasted: String, verifier: String, state: String) async throws -> ClaudeLoginResult {
        let trimmed = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: "#", maxSplits: 1).map(String.init)
        let code = parts.first ?? trimmed
        if parts.count == 2, parts[1] != state {
            throw ClaudeOAuthLoginError.stateMismatch
        }

        var req = URLRequest(url: ClaudeOAuthRefresher.tokenURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("claude-cli/1.0 (external, cli)", forHTTPHeaderField: "User-Agent")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "grant_type": "authorization_code",
            "code": code,
            "state": state,
            "client_id": ClaudeOAuthRefresher.clientID,
            "redirect_uri": redirectURI,
            "code_verifier": verifier,
        ])
        req.timeoutInterval = 30

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw ClaudeOAuthLoginError.badResponse("no HTTP response")
        }
        guard http.statusCode == 200,
              let obj = ClaudeJSON.object(from: data) else {
            throw ClaudeOAuthLoginError.badResponse("HTTP \(http.statusCode): \(String(decoding: data, as: UTF8.self).prefix(200))")
        }
        guard let access = obj["access_token"] as? String, !access.isEmpty else {
            throw ClaudeOAuthLoginError.badResponse("missing access_token")
        }
        return buildResult(from: obj, accessToken: access)
    }

    /// 토큰 응답 → Claude Code 자격증명 blob. 응답 형태 차이를 방어적으로 흡수한다.
    static func buildResult(from obj: [String: Any], accessToken: String) -> ClaudeLoginResult {
        let refresh = obj["refresh_token"] as? String
        let expiresAtMs = (obj["expires_in"] as? Double).map {
            (Date().timeIntervalSince1970 + $0) * 1000
        }
        let scopes = (obj["scope"] as? String)?.split(separator: " ").map(String.init)

        // organization / account 메타는 응답 위치가 다를 수 있어 여러 후보를 훑는다.
        let org = firstString(obj, ["organization", "uuid"])
            ?? firstString(obj, ["organization_uuid"])
            ?? firstString(obj, ["account", "organization_uuid"])
        let email = firstString(obj, ["account", "email_address"])
            ?? firstString(obj, ["account", "email"])
            ?? JwtEmailLite.email(from: accessToken)

        var oauth: [String: Any] = ["accessToken": accessToken]
        if let refresh { oauth["refreshToken"] = refresh }
        if let expiresAtMs { oauth["expiresAt"] = expiresAtMs }
        if let scopes { oauth["scopes"] = scopes }
        if let sub = obj["subscription_type"] as? String { oauth["subscriptionType"] = sub }

        var root: [String: Any] = ["claudeAiOauth": oauth]
        if let org { root["organizationUuid"] = org }
        let blob = ClaudeJSON.data(withJSONObject: root) ?? Data()
        return ClaudeLoginResult(blob: blob, organizationUuid: org, email: email)
    }

    // MARK: helpers

    private static func firstString(_ obj: [String: Any], _ path: [String]) -> String? {
        var cur: Any? = obj
        for key in path {
            cur = (cur as? [String: Any])?[key]
        }
        return (cur as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    private static func randomURLSafe(_ bytes: Int) -> String {
        var d = Data(count: bytes)
        _ = d.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, bytes, $0.baseAddress!) }
        return base64URL(d)
    }

    private static func base64URL(_ d: Data) -> String {
        d.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// accessToken(JWT) payload 의 email 추출(옵트). opaque 토큰이면 nil.
enum JwtEmailLite {
    static func email(from jwt: String) -> String? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var b64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64.append("=") }
        guard let data = Data(base64Encoded: b64),
              let obj = ClaudeJSON.object(from: data),
              let email = obj["email"] as? String, !email.isEmpty else { return nil }
        return email
    }
}
#endif
