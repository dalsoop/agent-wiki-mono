import Foundation
import Security

/// 접속 설정. 서버 주소는 UserDefaults, clientId/clientSecret 은 Keychain.
public struct ConnectionSettings: Sendable, Equatable {
    public var instanceBase: String
    public var clientId: String
    public var clientSecret: String
    public init(instanceBase: String = "", clientId: String = "", clientSecret: String = "") {
        self.instanceBase = instanceBase
        self.clientId = clientId
        self.clientSecret = clientSecret
    }
    public var isComplete: Bool {
        !instanceBase.isEmpty && !clientId.isEmpty && !clientSecret.isEmpty
    }
}

public protocol SettingsStoring: Sendable {
    func load() -> ConnectionSettings
    func save(_ settings: ConnectionSettings) throws
}

/// UserDefaults(주소) + Keychain generic password(자격) 저장.
public struct KeychainSettingsStore: SettingsStoring {
    private let service = "com.dalsoop.infisical-manager"
    private let baseKey = "infisical.instanceBase"
    /// 공유 Keychain access group. GUI 는 nil(자기 기본 그룹 = 앱 application-identifier)로 저장하고,
    /// 헤드리스 CLI 는 그 그룹(`<TeamID>.net.ranode.infisical`)을 지정해 같은 자격을 읽는다.
    private let accessGroup: String?

    public init(accessGroup: String? = nil) {
        self.accessGroup = accessGroup
    }

    public func load() -> ConnectionSettings {
        ConnectionSettings(
            instanceBase: UserDefaults.standard.string(forKey: baseKey) ?? "",
            clientId: read(account: "clientId") ?? "",
            clientSecret: read(account: "clientSecret") ?? ""
        )
    }

    public func save(_ settings: ConnectionSettings) throws {
        UserDefaults.standard.set(settings.instanceBase, forKey: baseKey)
        try write(account: "clientId", value: settings.clientId)
        try write(account: "clientSecret", value: settings.clientSecret)
    }

    private func query(account: String) -> [String: Any] {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecAttrAccount as String: account]
        if let accessGroup { q[kSecAttrAccessGroup as String] = accessGroup }
        return q
    }

    private func read(account: String) -> String? {
        var q = query(account: account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func write(account: String, value: String) throws {
        let data = Data(value.utf8)
        let base = query(account: account)
        let status = SecItemUpdate(base as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = base
            add[kSecValueData as String] = data
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw NSError(domain: NSOSStatusErrorDomain, code: Int(addStatus))
            }
        } else if status != errSecSuccess {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }
}
