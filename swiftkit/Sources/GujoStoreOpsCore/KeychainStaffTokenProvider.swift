import Foundation
#if canImport(Security)
import Security
#endif

/// Keychain service `net.ranode.gujo` account `staff` 읽기 전용.
/// macOS 와 iOS 가 같은 service/account 를 쓴다. 쓰기는 이 타입이 하지 않는다.
public struct KeychainStaffTokenProvider: StaffTokenProviding {
    public static let service = "net.ranode.gujo"
    public static let account = "staff"

    public init() {}

    public func staffToken() throws -> String? {
        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { return nil }
        guard let data = out as? Data else { return nil }
        let trimmed = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return nil }
        return trimmed
        #else
        return nil
        #endif
    }
}
