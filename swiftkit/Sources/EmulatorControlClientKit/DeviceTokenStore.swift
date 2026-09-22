import Foundation
#if os(macOS)
import KeychainKit
#endif

public protocol DeviceTokenStoring: Sendable {
    func loadToken() async -> String?
    func saveToken(_ token: String) async
    func deleteToken() async
}

public actor InMemoryDeviceTokenStore: DeviceTokenStoring {
    private var token: String?

    public init(token: String? = nil) {
        self.token = token
    }

    public func loadToken() -> String? {
        token
    }

    public func saveToken(_ token: String) {
        self.token = token
    }

    public func deleteToken() {
        token = nil
    }
}

/// File-based token store shared across all emulator-control apps.
/// Avoids macOS Keychain ACL per-binary restrictions that prevent
/// token sharing between separately built binaries.
/// Works on both macOS and Linux.
public struct SharedFileTokenStore: DeviceTokenStoring {
    public static let defaultURL: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("ranode-emulator-control", isDirectory: true)
        do { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) } catch { _ = error }
        return dir.appendingPathComponent("device-token")
    }()

    private let fileURL: URL

    public init(fileURL: URL = SharedFileTokenStore.defaultURL) {
        self.fileURL = fileURL
    }

    public func loadToken() async -> String? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func saveToken(_ token: String) async {
        let dir = fileURL.deletingLastPathComponent()
        do { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) } catch { _ = error }
        do { try token.write(to: fileURL, atomically: true, encoding: .utf8) } catch { _ = error }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    public func deleteToken() async {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

#if os(macOS)
public struct KeychainDeviceTokenStore: DeviceTokenStoring {
    /// Shared keychain service name for all emulator-control apps.
    public static let sharedService = "ranode-emulator-control"

    private let keychain: CachedKeychainStore
    private let account: String

    public init(
        service: String = KeychainDeviceTokenStore.sharedService,
        account: String = "emulator-control-device-token"
    ) {
        keychain = CachedKeychainStore(service: service)
        self.account = account
    }

    public func loadToken() async -> String? {
        keychain.string(account: account)
    }

    public func saveToken(_ token: String) async {
        keychain.set(token, account: account)
    }

    public func deleteToken() async {
        keychain.delete(account: account)
    }
}
#endif
