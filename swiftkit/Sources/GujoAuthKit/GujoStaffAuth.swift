import Foundation
import HTTPClientKit

/// 스태프 인증(계약 §1·§4). `GujoAuth.staff` 가 기본 인스턴스다.
///
/// - 로그인: device-code 폴링. `user_code`·`verification_uri` 는 `present` 훅으로 앱에 넘기고
///   앱이 **앱 안 표준 프롬프트**에 띄운다. 킷은 터미널에 아무것도 쓰지 않는다.
/// - 세션: Keychain(`net.ranode.gujo`/`staff`) → agent-vault 폴백 순. env 는 읽지 않는다.
/// - 호스트: EndpointRouterKit `gujo-core` 키만.
public struct GujoStaffAuth: Sendable {
    public typealias Sleeper = @Sendable (TimeInterval) async throws -> Void
    public typealias Clock = @Sendable () -> Date

    public enum Path {
        public static let deviceAuthorize = "/api/staff/device/authorize"
        public static let devicePoll = "/api/staff/device/token"
        public static let me = "/api/staff/me"
        public static let logout = "/api/staff/logout"
    }

    private let http: any HTTPClient
    private let store: any GujoSessionStore
    private let fallback: any StaffTokenFallback
    private let baseURLOverride: URL?
    private let sleep: Sleeper
    private let now: Clock

    /// - Parameters:
    ///   - http: 전송. 테스트는 스텁을 넣는다.
    ///   - store: 세션 저장소. 기본 Keychain.
    ///   - fallback: Keychain 이 비었을 때의 토큰 출처(기본 agent-vault 카드).
    ///   - baseURL: nil 이면 EndpointRouterKit `gujo-core`.
    ///   - sleep: 폴링 간격 대기. 테스트는 no-op.
    ///   - now: 시계. 만료 판정에 쓴다.
    public init(
        http: any HTTPClient = URLSessionHTTPClient(),
        store: any GujoSessionStore = GujoSessionStores.default(),
        fallback: any StaffTokenFallback = StaffTokenFallbacks.default(),
        baseURL: URL? = nil,
        sleep: @escaping Sleeper = { try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) },
        now: @escaping Clock = { Date() }
    ) {
        self.http = http
        self.store = store
        self.fallback = fallback
        self.baseURLOverride = baseURL
        self.sleep = sleep
        self.now = now
    }

    func transport() throws -> GujoJSONTransport {
        GujoJSONTransport(http: http, baseURL: try GujoCoreHost.resolve(override: baseURLOverride))
    }

    // MARK: - 로그인

    /// device-code 로그인. 승인될 때까지 `interval` 간격으로 폴링한다.
    /// - Parameters:
    ///   - client: 계약의 `client` 식별자(예: `gujo-commerce-desk`).
    ///   - deviceName: 승인 화면에 보일 기기 이름(기본 호스트명).
    ///   - present: 앱이 user_code·URL 을 표시하는 훅. 승인 전 한 번 호출된다.
    @discardableResult
    public func login(
        client: String,
        deviceName: String = ProcessInfo.processInfo.hostName,
        present: @escaping DeviceCodePresenter
    ) async throws -> StaffSession {
        let transport = try transport()
        let authorization = try await authorize(transport, client: client, deviceName: deviceName)
        let prompt = DeviceCodePrompt(
            userCode: authorization.userCode,
            verificationURI: authorization.verificationURL,
            expiresAt: authorization.expiresAt,
            pollInterval: authorization.interval)
        await present(prompt)

        var interval = authorization.interval
        while true {
            if Task.isCancelled { throw GujoAuthError.cancelled }
            guard now() < authorization.expiresAt else { throw GujoAuthError.deviceCodeExpired }
            try await sleep(interval)
            switch try await poll(transport, deviceCode: authorization.deviceCode) {
            case .approved(let session):
                store.save(session, account: GujoKeychain.staffAccount)
                return session
            case .pending:
                continue
            case .slowDown:
                interval += 5
            }
        }
    }

    private struct Authorization: Sendable {
        let deviceCode: String
        let userCode: String
        let verificationURL: URL
        let expiresAt: Date
        let interval: TimeInterval
    }

    private struct AuthorizeRequest: Encodable {
        let client: String
        let deviceName: String
    }

    private struct AuthorizeResponse: Decodable {
        let deviceCode: String
        let userCode: String
        let verificationUri: String
        let expiresIn: Int
        let interval: Int?
    }

    private func authorize(
        _ transport: GujoJSONTransport, client: String, deviceName: String
    ) async throws -> Authorization {
        let response = try await transport.send(
            method: "POST", path: Path.deviceAuthorize,
            json: AuthorizeRequest(client: client, deviceName: deviceName))
        guard (200..<300).contains(response.status) else {
            throw GujoAuthError.unexpectedStatus(response.status, error: response.errorBody?.error)
        }
        let decoded = try response.decode(AuthorizeResponse.self)
        guard let url = URL(string: decoded.verificationUri) else {
            throw GujoAuthError.malformedResponse("verification_uri 가 URL 이 아님")
        }
        return Authorization(
            deviceCode: decoded.deviceCode,
            userCode: decoded.userCode,
            verificationURL: url,
            expiresAt: now().addingTimeInterval(TimeInterval(decoded.expiresIn)),
            interval: TimeInterval(max(decoded.interval ?? 5, 1)))
    }

    private enum PollOutcome {
        case approved(StaffSession)
        case pending
        case slowDown
    }

    private struct TokenRequest: Encodable {
        let deviceCode: String
    }

    struct TokenResponse: Decodable {
        let token: String
        let tokenType: String?
        let expiresAt: Date
        let abilities: [String]
        let staff: StaffIdentity

        var session: StaffSession {
            StaffSession(
                token: token, tokenType: tokenType ?? "Bearer", expiresAt: expiresAt,
                abilityNames: abilities, staff: staff)
        }
    }

    private func poll(_ transport: GujoJSONTransport, deviceCode: String) async throws -> PollOutcome {
        let response = try await transport.send(
            method: "POST", path: Path.devicePoll, json: TokenRequest(deviceCode: deviceCode))
        switch response.status {
        case 200:
            return .approved(try response.decode(TokenResponse.self).session)
        case 428:
            return .pending
        case 429:
            return .slowDown
        case 410:
            throw GujoAuthError.deviceCodeExpired
        case 403:
            throw GujoAuthError.accessDenied
        default:
            throw GujoAuthError.unexpectedStatus(response.status, error: response.errorBody?.error)
        }
    }

    // MARK: - 세션 조회

    /// 현재 세션. Keychain → agent-vault 폴백(토큰만 있으면 `/api/staff/me` 로 채운다).
    public func current() async throws -> StaffSession {
        if let stored = store.load(StaffSession.self, account: GujoKeychain.staffAccount) {
            guard !stored.isExpired(now: now()) else {
                throw GujoAuthError.sessionExpired(expiresAt: stored.expiresAt)
            }
            return stored
        }
        guard let token = await fallback.staffToken() else { throw GujoAuthError.notLoggedIn }
        return try await me(token: token)
    }

    /// Keychain 에 저장된 세션만(네트워크·폴백 없음). UI 가 "로그인됨" 표시에 쓴다.
    public func stored() -> StaffSession? {
        store.load(StaffSession.self, account: GujoKeychain.staffAccount)
    }

    /// ability 검사. 없으면 `.missingAbility` 에 이름을 실어 던진다.
    @discardableResult
    public func require(_ ability: StaffAbility) async throws -> StaffSession {
        let session = try await current()
        guard session.has(ability) else { throw GujoAuthError.missingAbility(ability) }
        return session
    }

    struct MeResponse: Decodable {
        let staff: StaffIdentity
        let abilities: [String]
        let expiresAt: Date
    }

    /// `GET /api/staff/me` 로 토큰을 검증하고 세션을 만든다. 저장하지 않는다.
    public func me(token: String) async throws -> StaffSession {
        let transport = try transport()
        let response = try await transport.send(method: "GET", path: Path.me, bearer: "Bearer \(token)")
        switch response.status {
        case 200:
            let decoded = try response.decode(MeResponse.self)
            return StaffSession(
                token: token, expiresAt: decoded.expiresAt,
                abilityNames: decoded.abilities, staff: decoded.staff)
        case 401, 403:
            throw GujoAuthError.accessDenied
        default:
            throw GujoAuthError.unexpectedStatus(response.status, error: response.errorBody?.error)
        }
    }

    // MARK: - 로그아웃

    /// 로컬 세션을 지우고 서버 토큰을 폐기한다. 서버 폐기가 실패해도 로컬은 지워진다.
    /// - Returns: 서버가 204 로 폐기를 확인했으면 true.
    @discardableResult
    public func logout() async -> Bool {
        let stored = store.load(StaffSession.self, account: GujoKeychain.staffAccount)
        store.delete(account: GujoKeychain.staffAccount)
        guard let stored else { return false }
        do {
            let response = try await transport().send(
                method: "POST", path: Path.logout, bearer: stored.authorizationHeader)
            return response.status == 204 || response.status == 200
        } catch {
            return false
        }
    }

    /// 세션을 직접 심는다 — 마이그레이션·테스트용. 앱 로그인 경로는 `login` 이다.
    public func adopt(_ session: StaffSession) {
        store.save(session, account: GujoKeychain.staffAccount)
    }
}
