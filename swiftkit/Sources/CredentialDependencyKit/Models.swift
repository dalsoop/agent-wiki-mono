import Foundation

public enum CredentialProviderKind: String, Codable, CaseIterable, Sendable {
    case localKeychain
    case vaultwarden
    case infisical
    case custom
}

public enum CredentialProviderCapability: String, Codable, CaseIterable, Sendable {
    case listMetadata
    case resolveSecret
    case writeSecret
    case rotateSecret
}

/// 비밀이 어디에 있는지 설명하는 공급자. endpoint와 configuration에는 비밀을 넣지 않는다.
public struct CredentialProviderDescriptor: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var kind: CredentialProviderKind
    public var endpoint: String
    public var capabilities: Set<CredentialProviderCapability>
    public var configuration: [String: String]
    public var enabled: Bool

    public init(
        id: String,
        name: String,
        kind: CredentialProviderKind,
        endpoint: String = "",
        capabilities: Set<CredentialProviderCapability> = [.listMetadata, .resolveSecret],
        configuration: [String: String] = [:],
        enabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.endpoint = endpoint
        self.capabilities = capabilities
        self.configuration = configuration
        self.enabled = enabled
    }
}

public enum CredentialField: String, Codable, CaseIterable, Sendable {
    case password
    case username
    case token
    case value
}

/// 공급자 내부 항목을 가리키는 안정 참조. 실제 비밀은 포함하지 않는다.
public struct CredentialLocator: Codable, Equatable, Hashable, Sendable {
    public var providerID: String
    public var itemID: String
    public var path: String
    public var field: CredentialField

    public init(
        providerID: String,
        itemID: String,
        path: String = "",
        field: CredentialField = .password
    ) {
        self.providerID = providerID
        self.itemID = itemID
        self.path = path
        self.field = field
    }
}

public enum CredentialSecretState: String, Codable, CaseIterable, Sendable {
    case available
    case missing
    case locked
    case unknown
}

/// 화면·CLI에 노출 가능한 카드 메타데이터. 비밀값은 구조적으로 들어갈 수 없다.
public struct CredentialDescriptor: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var kind: String
    public var account: String
    public var host: String
    public var locator: CredentialLocator
    public var secretState: CredentialSecretState
    public var updatedAt: Date?

    public init(
        id: String,
        name: String,
        kind: String,
        account: String = "",
        host: String = "",
        locator: CredentialLocator,
        secretState: CredentialSecretState = .unknown,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.account = account
        self.host = host
        self.locator = locator
        self.secretState = secretState
        self.updatedAt = updatedAt
    }
}

public enum CredentialConsumerKind: String, Codable, CaseIterable, Sendable {
    case agent
    case application
    case service
    case custom
}

public enum CredentialDeliveryKind: String, Codable, CaseIterable, Sendable {
    case stdin
    case environment
}

public struct CredentialDelivery: Codable, Equatable, Hashable, Sendable {
    public var kind: CredentialDeliveryKind
    public var environmentKey: String?

    public static let stdin = CredentialDelivery(kind: .stdin)

    public static func environment(_ key: String) -> CredentialDelivery {
        CredentialDelivery(kind: .environment, environmentKey: key)
    }

    public init(kind: CredentialDeliveryKind, environmentKey: String? = nil) {
        self.kind = kind
        self.environmentKey = environmentKey
    }
}

public struct CredentialConsumerDescriptor: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var kind: CredentialConsumerKind
    public var executablePath: String
    public var supportedDeliveries: Set<CredentialDeliveryKind>
    public var enabled: Bool

    public init(
        id: String,
        name: String,
        kind: CredentialConsumerKind,
        executablePath: String,
        supportedDeliveries: Set<CredentialDeliveryKind> = [.stdin],
        enabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.executablePath = executablePath
        self.supportedDeliveries = supportedDeliveries
        self.enabled = enabled
    }
}

public enum CredentialDependencyAccess: String, Codable, CaseIterable, Sendable {
    case use
    case manage

    public var allowsManage: Bool { self == .manage }
}

public struct CredentialAuthorization: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var credentialID: String
    public var consumerID: String
    public var access: CredentialDependencyAccess
    public var expiresAt: Date?
    public var enabled: Bool
    /// 호스트 앱이 정의하는 테넌트/작업공간 경계. nil은 레거시 전역 범위다.
    public var scopeID: String?

    public init(
        id: String = UUID().uuidString,
        credentialID: String,
        consumerID: String,
        access: CredentialDependencyAccess,
        expiresAt: Date? = nil,
        enabled: Bool = true,
        scopeID: String? = nil
    ) {
        self.id = id
        self.credentialID = credentialID
        self.consumerID = consumerID
        self.access = access
        self.expiresAt = expiresAt
        self.enabled = enabled
        self.scopeID = scopeID
    }

    public func isActive(at date: Date = Date()) -> Bool {
        enabled && (expiresAt.map { $0 > date } ?? true)
    }
}

/// 한 카드가 한 소비자에게 어떤 방식으로 전달되는지 기록하는 의존성 edge.
public struct CredentialBinding: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var credentialID: String
    public var consumerID: String
    public var purpose: String
    public var delivery: CredentialDelivery
    public var arguments: [String]
    public var enabled: Bool
    /// 호스트 앱이 정의하는 테넌트/작업공간 경계.
    public var scopeID: String?

    public init(
        id: String = UUID().uuidString,
        credentialID: String,
        consumerID: String,
        purpose: String,
        delivery: CredentialDelivery = .stdin,
        arguments: [String] = [],
        enabled: Bool = true,
        scopeID: String? = nil
    ) {
        self.id = id
        self.credentialID = credentialID
        self.consumerID = consumerID
        self.purpose = purpose
        self.delivery = delivery
        self.arguments = arguments
        self.enabled = enabled
        self.scopeID = scopeID
    }
}

public struct CredentialDependencyCatalog: Codable, Equatable, Sendable {
    public var providers: [CredentialProviderDescriptor]
    public var credentials: [CredentialDescriptor]
    public var consumers: [CredentialConsumerDescriptor]
    public var authorizations: [CredentialAuthorization]
    public var bindings: [CredentialBinding]

    public init(
        providers: [CredentialProviderDescriptor] = [],
        credentials: [CredentialDescriptor] = [],
        consumers: [CredentialConsumerDescriptor] = [],
        authorizations: [CredentialAuthorization] = [],
        bindings: [CredentialBinding] = []
    ) {
        self.providers = providers
        self.credentials = credentials
        self.consumers = consumers
        self.authorizations = authorizations
        self.bindings = bindings
    }
}

/// 실제 비밀 전달용 일회성 객체. Codable 미채택으로 설정·상태 JSON 직렬화를 막는다.
public struct CredentialSecret: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let username: String?
    public let value: String
    public let fields: [String: String]

    public init(username: String? = nil, value: String, fields: [String: String] = [:]) {
        self.username = username
        self.value = value
        self.fields = fields
    }

    public var description: String { "CredentialSecret(<redacted>)" }
    public var debugDescription: String { description }
}

public struct CredentialConsumptionResult: Sendable, Equatable {
    public var exitCode: Int32
    public var standardOutput: String
    public var standardError: String

    public init(exitCode: Int32, standardOutput: String = "", standardError: String = "") {
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
    }
}

public protocol CredentialProviding: Sendable {
    var descriptor: CredentialProviderDescriptor { get }
    func listMetadata() async throws -> [CredentialDescriptor]
    func resolve(_ locator: CredentialLocator) async throws -> CredentialSecret
}

public protocol CredentialConsuming: Sendable {
    var descriptor: CredentialConsumerDescriptor { get }
    func consume(_ secret: CredentialSecret, binding: CredentialBinding) async throws -> CredentialConsumptionResult
}
