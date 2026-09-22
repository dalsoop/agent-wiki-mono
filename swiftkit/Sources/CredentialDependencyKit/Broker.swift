import Foundation

public enum CredentialDependencyError: Error, LocalizedError, Sendable {
    case denied(String)
    case providerUnavailable(String)
    case consumerUnavailable(String)
    case invalidLocator
    case processFailed(String)

    public var errorDescription: String? {
        switch self {
        case .denied(let reason): reason
        case .providerUnavailable(let id): "인증정보 공급자를 사용할 수 없습니다: \(id)"
        case .consumerUnavailable(let id): "인증정보 소비자를 사용할 수 없습니다: \(id)"
        case .invalidLocator: "인증정보 위치가 올바르지 않습니다"
        case .processFailed(let message): "소비자 실행 실패: \(message)"
        }
    }
}

/// 공급자와 소비자를 런타임에 연결한다. 판정 전에는 비밀을 resolve하지 않는다.
public actor CredentialDependencyBroker {
    public var catalog: CredentialDependencyCatalog
    private var providers: [String: any CredentialProviding]
    private var consumers: [String: any CredentialConsuming]

    public init(
        catalog: CredentialDependencyCatalog,
        providers: [any CredentialProviding] = [],
        consumers: [any CredentialConsuming] = []
    ) {
        self.catalog = catalog
        self.providers = Dictionary(uniqueKeysWithValues: providers.map { ($0.descriptor.id, $0) })
        self.consumers = Dictionary(uniqueKeysWithValues: consumers.map { ($0.descriptor.id, $0) })
    }

    public func register(provider: any CredentialProviding) {
        providers[provider.descriptor.id] = provider
    }

    public func register(consumer: any CredentialConsuming) {
        consumers[consumer.descriptor.id] = consumer
    }

    public func list(providerID: String) async throws -> [CredentialDescriptor] {
        guard let provider = providers[providerID] else {
            throw CredentialDependencyError.providerUnavailable(providerID)
        }
        return try await provider.listMetadata()
    }

    public func deliver(bindingID: String) async throws -> CredentialConsumptionResult {
        let decision = CredentialDependencyPolicy.bindingDecision(bindingID: bindingID, catalog: catalog)
        guard decision.isAllowed else {
            if case .denied(let reason) = decision { throw CredentialDependencyError.denied(reason) }
            throw CredentialDependencyError.denied("권한이 없습니다")
        }
        guard let binding = catalog.bindings.first(where: { $0.id == bindingID }),
              let credential = catalog.credentials.first(where: { $0.id == binding.credentialID }) else {
            throw CredentialDependencyError.invalidLocator
        }
        guard let provider = providers[credential.locator.providerID] else {
            throw CredentialDependencyError.providerUnavailable(credential.locator.providerID)
        }
        guard let consumer = consumers[binding.consumerID] else {
            throw CredentialDependencyError.consumerUnavailable(binding.consumerID)
        }
        let secret = try await provider.resolve(credential.locator)
        return try await consumer.consume(secret, binding: binding)
    }
}
