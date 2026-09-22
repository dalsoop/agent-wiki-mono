import Foundation
import os

/// License key bytes. Cloud Apps injects Keychain; tests inject memory.
public protocol LicenseSecretStore: Sendable {
    func data(account: String) -> Data?
    func setData(_ value: Data, account: String) throws
    func delete(account: String)
}

/// In-memory secret map. No Keychain, no disk.
public final class MemoryLicenseSecretStore: LicenseSecretStore, Sendable {
    private let memory: OSAllocatedUnfairLock<[String: Data]>

    public init(initial: [String: Data] = [:]) {
        memory = OSAllocatedUnfairLock(initialState: initial)
    }

    public func data(account: String) -> Data? {
        memory.withLock { $0[account] }
    }

    public func setData(_ value: Data, account: String) throws {
        memory.withLock { $0[account] = value }
    }

    public func delete(account: String) {
        memory.withLock { _ = $0.removeValue(forKey: account) }
    }
}
