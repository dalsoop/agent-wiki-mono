import Foundation

/// 고객 기기를 표시하는, 하드웨어 식별자와 분리된 앱별 설치 식별자.
///
/// `identifier`는 앱이 Keychain에 한 번 생성해 저장한 무작위 값이어야 한다. 하드웨어
/// 시리얼·광고 식별자 같은 개인정보를 라이선스 제공자에 보내지 않는다.
public struct LicenseDevice: Sendable, Equatable {
    public let identifier: String
    public let displayName: String

    public init(identifier: String, displayName: String) {
        self.identifier = identifier
        self.displayName = displayName
    }
}

/// 활성화된 라이선스의 민감한 기록. `licenseKey`는 반드시 Keychain에만 저장한다.
public struct LicenseActivation: Codable, Sendable, Equatable {
    public let providerIdentifier: String
    public let licenseKey: String
    public let activationIdentifier: String
    public let planIdentifier: String
    public let activatedAt: Date
    public let expiresAt: Date?

    public init(
        providerIdentifier: String,
        licenseKey: String,
        activationIdentifier: String,
        planIdentifier: String,
        activatedAt: Date,
        expiresAt: Date?
    ) {
        self.providerIdentifier = providerIdentifier
        self.licenseKey = licenseKey
        self.activationIdentifier = activationIdentifier
        self.planIdentifier = planIdentifier
        self.activatedAt = activatedAt
        self.expiresAt = expiresAt
    }
}

/// Keychain에 저장하는 활성화와 마지막 확정 검증 시각.
public struct LicenseRecord: Codable, Sendable, Equatable {
    public var activation: LicenseActivation
    public var lastValidatedAt: Date

    public init(activation: LicenseActivation, lastValidatedAt: Date) {
        self.activation = activation
        self.lastValidatedAt = lastValidatedAt
    }
}

/// 앱이 기능 게이트에 사용할 라이선스 상태.
public enum LicenseEntitlementState: Sendable, Equatable {
    case unlicensed(message: String)
    case active(planIdentifier: String, expiresAt: Date?)
    case gracePeriod(planIdentifier: String, expiresAt: Date?, until: Date, message: String)
    case expired(message: String)
    case invalid(message: String)

    public var allowsLicensedFeatures: Bool {
        switch self {
        case .active, .gracePeriod: true
        case .unlicensed, .expired, .invalid: false
        }
    }

    public var message: String {
        switch self {
        case .unlicensed(let message), .expired(let message), .invalid(let message): message
        case .active: "라이선스가 활성화되었습니다."
        case .gracePeriod(_, _, let until, let message): "\(message) · \(until.formatted(date: .abbreviated, time: .shortened))까지 오프라인 유예"
        }
    }
}

/// 제공자가 내리는 확정 판정. 네트워크 실패는 이 값이 아니라 `LicenseProviderError`로 표현한다.
public enum LicenseValidation: Sendable, Equatable {
    case valid(planIdentifier: String?, expiresAt: Date?)
    case invalid(message: String)
    case expired(message: String)
}

/// 라이선스 제공자 오류. `transient`만 오프라인 유예를 허용한다.
public enum LicenseProviderError: Error, Sendable, Equatable, LocalizedError {
    case transient(String)
    case rejected(String)
    case malformedResponse(String)
    case configuration(String)

    public var errorDescription: String? {
        switch self {
        case .transient(let message), .rejected(let message), .malformedResponse(let message), .configuration(let message): message
        }
    }

    public var isTransient: Bool {
        if case .transient = self { return true }
        return false
    }
}

public protocol LicenseProvider: Sendable {
    var providerIdentifier: String { get }
    func activate(licenseKey: String, device: LicenseDevice) async throws -> LicenseActivation
    func validate(_ activation: LicenseActivation) async throws -> LicenseValidation
    func deactivate(_ activation: LicenseActivation) async throws
}
