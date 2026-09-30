import CryptoKit
import Foundation
import HTTPClientKit

/// 스태프 인증(계약 §1·§4). `GujoAuth.staff` 가 기본 인스턴스다.
///
/// - 로그인: device-code 폴링. `user_code`·`verification_uri` 는 `present` 훅으로 앱에 넘기고
///   앱이 **앱 안 표준 프롬프트**에 띄운다. 킷은 터미널에 아무것도 쓰지 않는다.
/// - 세션: 기계 주체 토큰(sops 암호문, 계약 §6) → Keychain(`net.ranode.gujo`/`staff`) → agent-vault 폴백 순.
///   토큰 원문을 담은 env 는 읽지 않는다(`GUJO_STAFF_TOKEN_SOPS_FILE` 은 암호문 경로).
/// - 호스트: EndpointRouterKit `gujo-core` 키만.
public struct GujoStaffAuth: Sendable {
    public typealias Sleeper = @Sendable (TimeInterval) async throws -> Void
    public typealias Clock = @Sendable () -> Date

    /// 스태프 토큰 접두사(계약 §1).
    public static let tokenPrefix = "gst_"

    public enum Path {
        public static let deviceAuthorize = "/api/staff/device/authorize"
        public static let devicePoll = "/api/staff/device/token"
        public static let me = "/api/staff/me"
        public static let logout = "/api/staff/logout"
        public static let machineRotate = "/api/staff/machine/rotate"
        public static let refresh = "/api/staff/token/refresh"
    }

    private let http: any HTTPClient
    private let store: any GujoSessionStore
    private let fallback: any StaffTokenFallback
    private let machine: any MachineStaffTokenSource
    private let baseURLOverride: URL?
    private let sleep: Sleeper
    private let now: Clock

    /// - Parameters:
    ///   - http: 전송. 테스트는 스텁을 넣는다.
    ///   - store: 세션 저장소. 기본 Keychain.
    ///   - fallback: Keychain 이 비었을 때의 토큰 출처(기본 agent-vault 카드).
    ///   - machine: 사람 로그인보다 먼저 보는 기계 주체 토큰(기본 sops 암호문, 계약 §6).
    ///   - baseURL: nil 이면 EndpointRouterKit `gujo-core`.
    ///   - sleep: 폴링 간격 대기. 테스트는 no-op.
    ///   - now: 시계. 만료 판정에 쓴다.
    public init(
        http: any HTTPClient = URLSessionHTTPClient(),
        store: any GujoSessionStore = GujoSessionStores.default(),
        fallback: any StaffTokenFallback = StaffTokenFallbacks.default(),
        machine: any MachineStaffTokenSource = SopsMachineStaffToken(),
        baseURL: URL? = nil,
        sleep: @escaping Sleeper = { try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) },
        now: @escaping Clock = { Date() }
    ) {
        self.http = http
        self.store = store
        self.fallback = fallback
        self.machine = machine
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
            verificationURIComplete: authorization.verificationURLComplete,
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
        let verificationURLComplete: URL?
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
        let verificationUriComplete: String?
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
            verificationURLComplete: decoded.verificationUriComplete.flatMap(URL.init(string:)),
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
        /// 계약 §7: 짧은 access token + 회전형 갱신 토큰을 요청한다.
        let refresh = true
    }

    private struct RefreshRequest: Encodable {
        let refreshToken: String
    }

    struct TokenResponse: Decodable {
        let token: String
        let tokenType: String?
        let expiresAt: Date
        let abilities: [String]
        let staff: StaffIdentity
        let refreshToken: String?
        let refreshExpiresAt: Date?

        var session: StaffSession {
            StaffSession(
                token: token, tokenType: tokenType ?? "Bearer", expiresAt: expiresAt,
                abilityNames: abilities, staff: staff,
                refreshToken: refreshToken, refreshExpiresAt: refreshExpiresAt)
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

    /// 현재 세션. 기계 주체 토큰 → Keychain → agent-vault 폴백(토큰만 있으면 `/api/staff/me` 로 채운다).
    public func current() async throws -> StaffSession {
        if let token = machine.machineToken() {
            return try await me(token: token)
        }
        if let stored = store.load(StaffSession.self, account: GujoKeychain.staffAccount) {
            guard stored.isExpired(now: now()) else { return stored }
            guard stored.canRefresh(now: now()) else {
                throw GujoAuthError.sessionExpired(expiresAt: stored.expiresAt)
            }
            return try await refresh(stored)
        }
        guard let token = await fallback.staffToken() else { throw GujoAuthError.notLoggedIn }
        return try await me(token: token)
    }

    /// 요청에 붙일 토큰(네트워크 없음): 기계 주체 토큰, 없으면 만료되지 않은 사람 로그인 세션의 gst_ 토큰.
    /// 앱의 스태프 API 클라이언트가 이것 하나로 토큰을 고른다.
    public func bearerToken() -> String? {
        if let token = machine.machineToken() { return token }
        guard let session = store.load(StaffSession.self, account: GujoKeychain.staffAccount),
              session.token.hasPrefix(Self.tokenPrefix),
              !session.isExpired(now: now())
        else { return nil }
        return session.token
    }

    /// 요청에 붙일 토큰. 기계 주체 토큰 → 사람 세션(access token 이 만료됐으면 갱신 토큰으로 먼저 갱신, 계약 §7).
    /// 앱의 스태프 API 클라이언트는 요청마다 이것을 부른다.
    public func freshBearerToken() async throws -> String {
        if let token = machine.machineToken() { return token }
        guard let stored = store.load(StaffSession.self, account: GujoKeychain.staffAccount),
              stored.token.hasPrefix(Self.tokenPrefix)
        else { throw GujoAuthError.notLoggedIn }
        if !stored.isExpired(now: now()) { return stored.token }
        guard stored.canRefresh(now: now()) else { throw GujoAuthError.sessionExpired(expiresAt: stored.expiresAt) }
        return try await refresh(stored).token
    }

    /// 갱신 토큰으로 새 access·갱신 토큰을 받아 저장한다(계약 §7). 서버가 거절하면(재사용 감지로 계열이 폐기된 경우
    /// 포함) 저장된 세션을 지우고 다시 로그인하라고 던진다.
    @discardableResult
    public func refresh(_ session: StaffSession) async throws -> StaffSession {
        guard let refreshToken = session.refreshToken else { throw GujoAuthError.sessionExpired(expiresAt: session.expiresAt) }
        let response = try await transport().send(
            method: "POST", path: Path.refresh, json: RefreshRequest(refreshToken: refreshToken))
        switch response.status {
        case 200:
            let renewed = try response.decode(TokenResponse.self).session
            store.save(renewed, account: GujoKeychain.staffAccount)
            return renewed
        case 401:
            store.delete(account: GujoKeychain.staffAccount)
            throw GujoAuthError.notLoggedIn
        default:
            throw GujoAuthError.unexpectedStatus(response.status, error: response.errorBody?.error)
        }
    }

    /// 기계 주체 토큰(계약 §6). 없으면 nil. 앱 토큰 공급자가 사람 세션보다 먼저 본다.
    public func machineToken() -> String? { machine.machineToken() }

    /// 기계 주체 토큰을 쓰는 중인가(원문 없음). doctor·상태 표시용.
    public var usesMachineToken: Bool { machine.machineToken() != nil }

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

    // MARK: - 기계 주체 토큰 로테이션(계약 §6)

    /// 기계 주체 토큰이 후속 토큰을 받는다. 일회용 X25519 키를 만들어 `seal_to` 로 보내고, 서버가 봉인한 상자를
    /// 그 키로 연다 — 응답 어디에도 원문이 없다. 부른 토큰은 서버 유예(기본 10분) 뒤 만료되고 다시 로테이션할 수 없다.
    /// 결과는 저장하지 않는다 — 호출한 쪽(environment-secret-broker)이 곧바로 sops 암호문을 바꾼다.
    public func rotateMachineToken(current token: String) async throws -> MachineTokenRotation {
        let key = Curve25519.KeyAgreement.PrivateKey()
        let response = try await transport().send(
            method: "POST", path: Path.machineRotate, bearer: "Bearer \(token)",
            json: RotateRequest(sealTo: key.publicKey.rawRepresentation.base64EncodedString()))
        switch response.status {
        case 200:
            let decoded = try response.decode(RotateResponse.self)
            let opened = try decoded.sealedToken.open(with: key)
            guard opened.hasPrefix(Self.tokenPrefix) else {
                throw GujoAuthError.malformedResponse("sealed_token 이 gst_ 토큰이 아님")
            }
            return MachineTokenRotation(token: opened, expiresAt: decoded.expiresAt, abilities: decoded.abilities)
        case 401:
            throw GujoAuthError.accessDenied
        default:
            throw GujoAuthError.unexpectedStatus(response.status, error: response.errorBody?.error)
        }
    }

    private struct RotateRequest: Encodable {
        let sealTo: String
    }

    private struct RotateResponse: Decodable {
        let sealedToken: SealedTokenBox
        let expiresAt: Date
        let abilities: [String]
    }

    // MARK: - 로그아웃

    /// 로컬 세션을 지우고 서버 토큰을 폐기한다. 서버 폐기가 실패해도 로컬은 지워진다.
    /// - Returns: 서버가 204 로 폐기를 확인했으면 true.
    @discardableResult
    public func logout() async -> Bool {
        guard var stored = store.load(StaffSession.self, account: GujoKeychain.staffAccount) else { return false }
        // access token 이 만료됐으면 먼저 갱신해야 서버가 계열 전체를 폐기할 수 있다(계약 §7).
        if stored.isExpired(now: now()), stored.canRefresh(now: now()) {
            do {
                stored = try await refresh(stored)
            } catch {
                store.delete(account: GujoKeychain.staffAccount)
                return false
            }
        }
        store.delete(account: GujoKeychain.staffAccount)
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
