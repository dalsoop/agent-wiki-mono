import Foundation
import HTTPClientKit

/// 구매자 인증 — 기존 `/api/cli/device/authorize` · `/api/cli/device/token` 흐름을 스태프와 같은
/// 모양(`login/current/logout`)으로 감싼다. Keychain 자리는 `net.ranode.gujo`/`buyer`.
///
/// 옛 흐름과의 차이: 승인 대기는 **202** 이고(스태프는 428), 토큰 필드는 `account_token` 이다.
public struct GujoBuyerAuth: Sendable {
    public enum Path {
        public static let deviceAuthorize = "/api/cli/device/authorize"
        public static let devicePoll = "/api/cli/device/token"
    }

    private let http: any HTTPClient
    private let store: any GujoSessionStore
    private let baseURLOverride: URL?
    private let sleep: GujoStaffAuth.Sleeper
    private let now: GujoStaffAuth.Clock

    public init(
        http: any HTTPClient = URLSessionHTTPClient(),
        store: any GujoSessionStore = KeychainSessionStore(),
        baseURL: URL? = nil,
        sleep: @escaping GujoStaffAuth.Sleeper = { try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) },
        now: @escaping GujoStaffAuth.Clock = { Date() }
    ) {
        self.http = http
        self.store = store
        self.baseURLOverride = baseURL
        self.sleep = sleep
        self.now = now
    }

    private struct AuthorizeRequest: Encodable {
        let clientName: String
    }

    private struct AuthorizeResponse: Decodable {
        let deviceCode: String
        let userCode: String
        let verificationUri: String
        let verificationUriComplete: String?
        let expiresIn: Int
        let interval: Int?
    }

    private struct TokenRequest: Encodable {
        let deviceCode: String
    }

    private struct TokenResponse: Decodable {
        let accountToken: String
    }

    /// device-code 로그인. `present` 에는 `verification_uri_complete`(코드가 박힌 URL)가 있으면 그걸 준다.
    @discardableResult
    public func login(
        clientName: String = "Gujo Device SSO",
        present: @escaping DeviceCodePresenter
    ) async throws -> BuyerSession {
        let transport = GujoJSONTransport(
            http: http, baseURL: try GujoCoreHost.resolve(override: baseURLOverride))
        let response = try await transport.send(
            method: "POST", path: Path.deviceAuthorize, json: AuthorizeRequest(clientName: clientName))
        guard (200..<300).contains(response.status) else {
            throw GujoAuthError.unexpectedStatus(response.status, error: response.errorBody?.error)
        }
        let decoded = try response.decode(AuthorizeResponse.self)
        guard let url = URL(string: decoded.verificationUriComplete ?? decoded.verificationUri) else {
            throw GujoAuthError.malformedResponse("verification_uri 가 URL 이 아님")
        }
        let expiresAt = now().addingTimeInterval(TimeInterval(decoded.expiresIn))
        let interval = TimeInterval(max(decoded.interval ?? 5, 1))
        await present(DeviceCodePrompt(
            userCode: decoded.userCode, verificationURI: url, expiresAt: expiresAt, pollInterval: interval))

        while true {
            if Task.isCancelled { throw GujoAuthError.cancelled }
            guard now() < expiresAt else { throw GujoAuthError.deviceCodeExpired }
            try await sleep(interval)
            let poll = try await transport.send(
                method: "POST", path: Path.devicePoll, json: TokenRequest(deviceCode: decoded.deviceCode))
            switch poll.status {
            case 200:
                let session = BuyerSession(token: try poll.decode(TokenResponse.self).accountToken)
                store.save(session, account: GujoKeychain.buyerAccount)
                return session
            case 202, 428:
                continue
            case 410:
                throw GujoAuthError.deviceCodeExpired
            case 403:
                throw GujoAuthError.accessDenied
            default:
                throw GujoAuthError.unexpectedStatus(poll.status, error: poll.errorBody?.error)
            }
        }
    }

    /// 저장된 구매자 세션. 없으면 nil(구매자는 폴백이 없다).
    public func current() -> BuyerSession? {
        store.load(BuyerSession.self, account: GujoKeychain.buyerAccount)
    }

    public func logout() {
        store.delete(account: GujoKeychain.buyerAccount)
    }
}
