import Foundation

/// 스태프 신원(계약 §1 `staff` 객체).
public struct StaffIdentity: Codable, Equatable, Sendable {
    public var id: Int
    public var name: String
    public var email: String

    public init(id: Int, name: String, email: String) {
        self.id = id
        self.name = name
        self.email = email
    }
}

/// 로그인된 스태프 세션 — Keychain(service "net.ranode.gujo", account "staff") 에 JSON 그대로 저장된다.
///
/// abilities 는 서버 문자열을 그대로 보관한다(`abilityNames`). 클라이언트가 모르는 새 ability 가
/// 서버에 생겨도 세션 디코딩이 깨지지 않게 하기 위해서다. 타입 조회는 `abilities`/`has(_:)`.
public struct StaffSession: Codable, Equatable, Sendable {
    public var token: String
    public var tokenType: String
    public var expiresAt: Date
    public var abilityNames: [String]
    public var staff: StaffIdentity

    public init(
        token: String,
        tokenType: String = "Bearer",
        expiresAt: Date,
        abilityNames: [String],
        staff: StaffIdentity
    ) {
        self.token = token
        self.tokenType = tokenType
        self.expiresAt = expiresAt
        self.abilityNames = abilityNames
        self.staff = staff
    }

    public init(
        token: String,
        tokenType: String = "Bearer",
        expiresAt: Date,
        abilities: [StaffAbility],
        staff: StaffIdentity
    ) {
        self.init(
            token: token, tokenType: tokenType, expiresAt: expiresAt,
            abilityNames: abilities.map(\.rawValue), staff: staff)
    }

    /// 클라이언트가 아는 abilities 만. 모르는 이름은 `abilityNames` 에만 남는다.
    public var abilities: Set<StaffAbility> {
        Set(abilityNames.compactMap(StaffAbility.init(rawValue:)))
    }

    enum CodingKeys: String, CodingKey {
        case token, tokenType, expiresAt, staff
        /// 서버 토큰 응답·Keychain JSON 모두 `abilities`(계약 §1·§4).
        case abilityNames = "abilities"
    }

    public func has(_ ability: StaffAbility) -> Bool {
        abilityNames.contains(ability.rawValue)
    }

    public func isExpired(now: Date = Date()) -> Bool {
        expiresAt <= now
    }

    /// `Authorization` 헤더 값.
    public var authorizationHeader: String { "\(tokenType) \(token)" }
}

/// 구매자 세션 — 기존 `/api/cli/device/*` 흐름의 계정 토큰(account "buyer").
public struct BuyerSession: Codable, Equatable, Sendable {
    public var token: String
    public var tokenType: String

    public init(token: String, tokenType: String = "Bearer") {
        self.token = token
        self.tokenType = tokenType
    }

    public var authorizationHeader: String { "\(tokenType) \(token)" }
}

/// device-code 승인 화면에 띄울 정보. 앱은 이걸 **앱 안 표준 프롬프트**로 보여준다.
/// 킷은 터미널에 아무것도 출력하지 않는다.
public struct DeviceCodePrompt: Equatable, Sendable {
    public var userCode: String
    public var verificationURI: URL
    public var expiresAt: Date
    public var pollInterval: TimeInterval

    public init(userCode: String, verificationURI: URL, expiresAt: Date, pollInterval: TimeInterval) {
        self.userCode = userCode
        self.verificationURI = verificationURI
        self.expiresAt = expiresAt
        self.pollInterval = pollInterval
    }
}

/// 앱이 프롬프트를 표시하는 훅. 승인 대기 중 폴링은 킷이 한다.
public typealias DeviceCodePresenter = @Sendable (DeviceCodePrompt) async -> Void
