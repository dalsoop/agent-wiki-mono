import Foundation
#if canImport(Security)
import Security
#endif

/// GUI 표준 프롬프트에서만 호출. 평문 파일을 **확인 후에** 읽어 Keychain 에 넣고 파일을 지운다.
/// 인증 기본 경로(`StaffTokenProviding`)는 이 타입을 거치지 않는다.
public enum LegacyStaffTokenImporter: Sendable {
    public static func importAndDelete(path: String, fileManager: FileManager) throws {
        let raw: String
        do {
            raw = try String(contentsOfFile: path, encoding: .utf8)
        } catch {
            throw StoreOpsError.network("legacy token file unreadable")
        }
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw StoreOpsError.network("legacy token file empty") }
        try writeKeychain(token)
        try fileManager.removeItem(atPath: path)
    }

    public static func writeKeychain(_ token: String) throws {
        #if canImport(Security)
        let service = KeychainStaffTokenProvider.service
        let account = KeychainStaffTokenProvider.account
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(token.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw StoreOpsError.network("keychain write failed (\(status))")
        }
        #else
        throw StoreOpsError.notImplemented("keychain unavailable")
        #endif
    }
}
