#if canImport(Security)
import Foundation
import Security

public enum KeychainPersistentReference {
    public enum Error: Swift.Error, Sendable, Equatable {
        case status(OSStatus)
        case notUTF8
    }

    public static func readString(persistentReference: Data) -> Result<String, Error> {
        var out: CFTypeRef?
        let status = SecItemCopyMatching([
            kSecValuePersistentRef as String: persistentReference,
            kSecReturnData as String: true
        ] as CFDictionary, &out)
        guard status == errSecSuccess else { return .failure(.status(status)) }
        guard let data = out as? Data, let text = String(data: data, encoding: .utf8) else {
            return .failure(.notUTF8)
        }
        return .success(text)
    }

    public static func store(
        service: String,
        account: String,
        value: Data,
        description: String? = nil,
        accessible: CFString = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        trustedAccess: KeychainTrustedAccess? = nil
    ) -> Data? {
        _ = delete(service: service, account: account)
        var query = KeychainItemIO.base(service: service, account: account)
        query[kSecValueData as String] = value
        if let description {
            query[kSecAttrDescription as String] = description
        }
        query[kSecAttrSynchronizable as String] = false
        query[kSecAttrAccessible as String] = accessible
        #if os(macOS)
        if let access = KeychainItemIO.makeAccess(trustedAccess) {
            query[kSecAttrAccess as String] = access
        }
        #endif
        query[kSecReturnPersistentRef as String] = true
        var out: CFTypeRef?
        guard SecItemAdd(query as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    @discardableResult
    public static func delete(service: String, account: String) -> OSStatus {
        let query = KeychainItemIO.base(service: service, account: account)
        return SecItemDelete(query as CFDictionary)
    }
}
#endif
