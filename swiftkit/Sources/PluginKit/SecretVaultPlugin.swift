import Foundation
import InteropKit

/// 시크릿 및 자격증명을 안전하게 관리하는 플러그인(Interop Adapter) 표준 인터페이스.
/// 평문 비밀을 페이로드 딕셔너리로 반환하지 않고, 순정 CLI argv 및 토큰 규약을 준수합니다.
public protocol SecretVaultPlugin: AppPlugin {
    /// 시크릿 값 조회 (인프로세스 전용 또는 안전한 핸들러)
    func getSecret(key: String, tenantId: String?) async throws -> String?
    
    /// 시크릿 값 저장
    func setSecret(key: String, value: String, tenantId: String?) async throws
    
    /// 시크릿 값 삭제
    func deleteSecret(key: String, tenantId: String?) async throws -> Bool
    
    /// 저장된 시크릿 키 목록 조회
    func listSecrets(tenantId: String?) async throws -> [String]
}

public extension SecretVaultPlugin {
    var actions: [String] {
        ["get", "set", "delete", "list"]
    }
    
    func execute(action: String, argv: [String]) async throws -> [String: Sendable] {
        switch action {
        case "get":
            guard let key = argv.first else {
                throw PluginError.invalidPayload("조회할 키가 지정되지 않았습니다.")
            }
            let secret = try await getSecret(key: key, tenantId: nil)
            return ["status": "ok", "key": key, "found": secret != nil]
            
        case "set":
            guard argv.count >= 2 else {
                throw PluginError.invalidPayload("key와 value가 필요합니다.")
            }
            try await setSecret(key: argv[0], value: argv[1], tenantId: nil)
            return ["status": "ok", "key": argv[0]]
            
        case "delete":
            guard let key = argv.first else {
                throw PluginError.invalidPayload("삭제할 키가 지정되지 않았습니다.")
            }
            let deleted = try await deleteSecret(key: key, tenantId: nil)
            return ["status": "ok", "key": key, "deleted": deleted]
            
        case "list":
            let keys = try await listSecrets(tenantId: nil)
            return ["status": "ok", "count": keys.count, "keys": keys]
            
        default:
            throw PluginError.actionNotFound(action: action, pluginId: id)
        }
    }
}

/// CLI 기반 Vault 프로세스를 SecretVaultPlugin 인터페이스로 감싸는 어댑터
public struct CLIProcessSecretVaultAdapter: SecretVaultPlugin {
    public let id: String
    public let name: String
    public let version: String
    public let actions: [String]
    public let dependencies: [String]
    public let adapter: CLIProcessPluginAdapter
    
    public init(
        id: String = "secret-vault-adapter",
        name: String = "Secret Vault Adapter",
        version: String = "1.0.0",
        actions: [String] = ["get", "set", "delete", "list"],
        dependencies: [String] = [],
        executablePath: String
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.actions = actions
        self.dependencies = dependencies
        self.adapter = CLIProcessPluginAdapter(
            id: id,
            name: name,
            version: version,
            actions: actions,
            dependencies: dependencies,
            executablePath: executablePath
        )
    }
    
    public func getSecret(key: String, tenantId: String?) async throws -> String? {
        let res = try await adapter.execute(action: "get", argv: ["password", key, "--json"])
        return res["value"] as? String ?? res["rawOutput"] as? String
    }
    
    public func setSecret(key: String, value: String, tenantId: String?) async throws {
        _ = try await adapter.execute(action: "set", argv: ["password", key, value, "--json"])
    }
    
    public func deleteSecret(key: String, tenantId: String?) async throws -> Bool {
        let res = try await adapter.execute(action: "delete", argv: [key, "--json"])
        return (res["deleted"] as? Bool) ?? true
    }
    
    public func listSecrets(tenantId: String?) async throws -> [String] {
        let res = try await adapter.execute(action: "list", argv: ["--json"])
        return (res["keys"] as? [String]) ?? []
    }
    
    public func execute(action: String, argv: [String]) async throws -> [String: Sendable] {
        try await adapter.execute(action: action, argv: argv)
    }
}
