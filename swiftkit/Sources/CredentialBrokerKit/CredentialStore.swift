import Foundation
import KeychainKit

public protocol CredentialStoring: Sendable {
    func save(_ profile: String, _ credential: StoredCredential) async throws
    func load(_ profile: String) async throws -> StoredCredential?
    func delete(_ profile: String) async throws
    func profiles() async throws -> [String]
}

public struct KeychainCredentialStore: CredentialStoring {
    public let service: String
    private let store: CachedKeychainStore
    public init(service: String = "CredentialBroker.credential") {
        self.service = service
        self.store = CachedKeychainStore(service: service, accessible: kSecAttrAccessibleWhenUnlocked as CFString, readTimeout: 0)
    }
    public func save(_ profile: String, _ credential: StoredCredential) async throws { store.setData(try JSONEncoder().encode(credential), account: profile) }
    public func load(_ profile: String) async throws -> StoredCredential? {
        guard let data = store.data(account: profile) else { return nil }
        return try JSONDecoder().decode(StoredCredential.self, from: data)
    }
    public func delete(_ profile: String) async throws { store.delete(account: profile) }
    public func profiles() async throws -> [String] { store.listAccounts() }
}

public actor InMemoryCredentialStore: CredentialStoring {
    private var items: [String: StoredCredential] = [:]
    public init() {}
    public func save(_ profile: String, _ credential: StoredCredential) async throws { items[profile] = credential }
    public func load(_ profile: String) async throws -> StoredCredential? { items[profile] }
    public func delete(_ profile: String) async throws { items[profile] = nil }
    public func profiles() async throws -> [String] { items.keys.sorted() }
}
