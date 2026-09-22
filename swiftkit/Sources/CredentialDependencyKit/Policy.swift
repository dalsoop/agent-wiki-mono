import Foundation

public enum CredentialDependencyDecision: Equatable, Sendable {
    case allowed(CredentialDependencyAccess)
    case denied(String)

    public var isAllowed: Bool {
        if case .allowed = self { return true }
        return false
    }
}

public struct CredentialDependencyIssue: Identifiable, Codable, Equatable, Sendable {
    public enum Severity: String, Codable, Sendable { case warning, error }
    public var id: String
    public var severity: Severity
    public var message: String

    public init(id: String, severity: Severity, message: String) {
        self.id = id
        self.severity = severity
        self.message = message
    }
}

public enum CredentialDependencyPolicy {
    public static func decision(
        credentialID: String,
        consumerID: String,
        catalog: CredentialDependencyCatalog,
        scopeID: String? = nil,
        now: Date = Date()
    ) -> CredentialDependencyDecision {
        guard let credential = catalog.credentials.first(where: { $0.id == credentialID }) else {
            return .denied("인증정보를 찾을 수 없습니다")
        }
        guard let provider = catalog.providers.first(where: { $0.id == credential.locator.providerID }),
              provider.enabled else {
            return .denied("인증정보 공급자가 없거나 비활성 상태입니다")
        }
        guard let consumer = catalog.consumers.first(where: { $0.id == consumerID }), consumer.enabled else {
            return .denied("소비자가 없거나 비활성 상태입니다")
        }
        let active = catalog.authorizations.filter {
            $0.credentialID == credentialID && $0.consumerID == consumerID
                && (scopeID == nil || $0.scopeID == scopeID) && $0.isActive(at: now)
        }
        if active.contains(where: { $0.access == .manage }) { return .allowed(.manage) }
        if active.contains(where: { $0.access == .use }) { return .allowed(.use) }
        return .denied("이 인증정보에 대한 권한이 없습니다")
    }

    public static func managementDecision(
        credentialID: String,
        consumerID: String,
        catalog: CredentialDependencyCatalog,
        scopeID: String? = nil,
        now: Date = Date()
    ) -> CredentialDependencyDecision {
        switch decision(
            credentialID: credentialID, consumerID: consumerID,
            catalog: catalog, scopeID: scopeID, now: now) {
        case .allowed(.manage): return .allowed(.manage)
        case .allowed(.use): return .denied("이 인증정보의 관리 권한이 없습니다")
        case .denied(let reason): return .denied(reason)
        }
    }

    public static func bindingDecision(
        bindingID: String,
        catalog: CredentialDependencyCatalog,
        now: Date = Date()
    ) -> CredentialDependencyDecision {
        guard let binding = catalog.bindings.first(where: { $0.id == bindingID }), binding.enabled else {
            return .denied("의존성이 없거나 비활성 상태입니다")
        }
        guard let consumer = catalog.consumers.first(where: { $0.id == binding.consumerID }),
              consumer.supportedDeliveries.contains(binding.delivery.kind) else {
            return .denied("소비자가 이 전달 방식을 지원하지 않습니다")
        }
        if binding.delivery.kind == .environment,
           !isValidEnvironmentKey(binding.delivery.environmentKey) {
            return .denied("환경변수 이름이 올바르지 않습니다")
        }
        return decision(
            credentialID: binding.credentialID,
            consumerID: binding.consumerID,
            catalog: catalog,
            scopeID: binding.scopeID,
            now: now)
    }

    public static func dependencyCount(credentialID: String, catalog: CredentialDependencyCatalog) -> Int {
        catalog.authorizations.count { $0.credentialID == credentialID }
            + catalog.bindings.count { $0.credentialID == credentialID }
    }

    public static func validate(_ catalog: CredentialDependencyCatalog) -> [CredentialDependencyIssue] {
        var issues: [CredentialDependencyIssue] = []
        let providerIDs = Set(catalog.providers.map(\.id))
        let credentialIDs = Set(catalog.credentials.map(\.id))
        let consumerIDs = Set(catalog.consumers.map(\.id))

        for credential in catalog.credentials where !providerIDs.contains(credential.locator.providerID) {
            issues.append(.init(
                id: "credential-provider:\(credential.id)", severity: .error,
                message: "\(credential.name): 공급자 \(credential.locator.providerID)가 없습니다"))
        }
        for authorization in catalog.authorizations {
            if !credentialIDs.contains(authorization.credentialID) {
                issues.append(.init(
                    id: "authorization-credential:\(authorization.id)", severity: .error,
                    message: "권한이 없는 인증정보 \(authorization.credentialID)를 참조합니다"))
            }
            if !consumerIDs.contains(authorization.consumerID) {
                issues.append(.init(
                    id: "authorization-consumer:\(authorization.id)", severity: .error,
                    message: "권한이 없는 소비자 \(authorization.consumerID)를 참조합니다"))
            }
        }
        for binding in catalog.bindings {
            if !credentialIDs.contains(binding.credentialID) || !consumerIDs.contains(binding.consumerID) {
                issues.append(.init(
                    id: "binding-reference:\(binding.id)", severity: .error,
                    message: "\(binding.purpose): 인증정보 또는 소비자 참조가 끊겼습니다"))
                continue
            }
            if case .denied(let reason) = bindingDecision(bindingID: binding.id, catalog: catalog) {
                issues.append(.init(
                    id: "binding-policy:\(binding.id)", severity: .warning,
                    message: "\(binding.purpose): \(reason)"))
            }
        }
        return issues
    }

    public static func executableMatches(expectedPath: String, requestedPath: String) -> Bool {
        guard !expectedPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        let expected = canonicalPath(expectedPath)
        let requested = canonicalPath(requestedPath)
        if expected.hasSuffix(".app") { return requested.hasPrefix(expected + "/Contents/") }
        return requested == expected
    }

    private static func isValidEnvironmentKey(_ key: String?) -> Bool {
        guard let key, let first = key.first, first == "_" || first.isLetter else { return false }
        return key.allSatisfy { $0 == "_" || $0.isLetter || $0.isNumber }
    }

    private static func canonicalPath(_ path: String) -> String {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            .standardizedFileURL.resolvingSymlinksInPath().path
    }
}
