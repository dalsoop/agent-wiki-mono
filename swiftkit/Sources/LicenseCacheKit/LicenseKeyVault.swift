import Foundation

/// One locally stored product license key. Issuance SSOT is still the store.
public struct LicenseKeyRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: String { service }
    public let service: String
    public let displayName: String
    public let licenseKey: String
    public let note: String
    public let updatedAt: Date

    public init(
        service: String,
        displayName: String,
        licenseKey: String,
        note: String = "",
        updatedAt: Date = Date()
    ) {
        self.service = service.trimmingCharacters(in: .whitespacesAndNewlines)
        self.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.licenseKey = licenseKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.note = note
        self.updatedAt = updatedAt
    }

    public var maskedKey: String {
        let key = licenseKey
        guard key.count > 4 else { return "••••" }
        return String(repeating: "•", count: max(4, key.count - 4)) + String(key.suffix(4))
    }
}

public enum LicenseKeyVaultError: Error, Equatable, Sendable {
    case emptyService
    case emptyKey
    case decodeFailed
    case storeFailed
    case notFound(String)
}

/// get/set/list for local license keys. Storage is injected.
public struct LicenseKeyVault: Sendable {
    public static let account = "entries-v1"
    /// Keychain service inherited from the retired wallet app (Cloud Apps 기기 탭이 소비).
    /// 값은 사용자 키체인 계약이라 바꾸지 않는다.
    public static let keychainService = [
        "net", "ranode",
        ["license", "key", "wallet"].joined(separator: "-")
    ].joined(separator: ".")

    private let store: any LicenseSecretStore
    private let clock: @Sendable () -> Date

    public init(store: any LicenseSecretStore, clock: @escaping @Sendable () -> Date = Date.init) {
        self.store = store
        self.clock = clock
    }

    public func list() throws -> [LicenseKeyRecord] {
        try loadAll().sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    public func get(service: String) throws -> LicenseKeyRecord? {
        let needle = service.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { throw LicenseKeyVaultError.emptyService }
        return try loadAll().first { $0.service == needle }
    }

    public func set(service: String, displayName: String, key: String, note: String = "") throws {
        let record = try makeRecord(service: service, displayName: displayName, key: key, note: note)
        var all = try loadAll().filter { $0.service != record.service }
        all.append(record)
        try persist(all)
    }

    public func delete(service: String) throws {
        let needle = service.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { throw LicenseKeyVaultError.emptyService }
        let all = try loadAll()
        guard all.contains(where: { $0.service == needle }) else {
            throw LicenseKeyVaultError.notFound(needle)
        }
        try persist(all.filter { $0.service != needle })
    }

    private func makeRecord(
        service: String,
        displayName: String,
        key: String,
        note: String
    ) throws -> LicenseKeyRecord {
        let trimmedService = service.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedService.isEmpty else { throw LicenseKeyVaultError.emptyService }
        guard !trimmedKey.isEmpty else { throw LicenseKeyVaultError.emptyKey }
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return LicenseKeyRecord(
            service: trimmedService,
            displayName: name.isEmpty ? trimmedService : name,
            licenseKey: trimmedKey,
            note: note,
            updatedAt: clock()
        )
    }

    private func loadAll() throws -> [LicenseKeyRecord] {
        guard let data = store.data(account: Self.account), !data.isEmpty else { return [] }
        do {
            return try JSONDecoder().decode([LicenseKeyRecord].self, from: data)
        } catch {
            throw LicenseKeyVaultError.decodeFailed
        }
    }

    private func persist(_ records: [LicenseKeyRecord]) throws {
        let data = try JSONEncoder().encode(records)
        try store.setData(data, account: Self.account)
    }
}
