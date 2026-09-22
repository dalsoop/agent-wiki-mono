import Foundation

public struct DeviceIdentity: Codable, Sendable, Equatable {
    public let deviceId: String
    public let os: String
    public let hostname: String
    public let registeredAt: Date
    public init(deviceId: String, os: String, hostname: String, registeredAt: Date) {
        self.deviceId = deviceId
        self.os = os
        self.hostname = hostname
        self.registeredAt = registeredAt
    }
}

public final class DeviceStore: Sendable {
    private let file: URL
    private let access: LedgerWriteAccess
    public init(file: URL = AppPaths.deviceFile, access: LedgerWriteAccess = .cloudApps) {
        self.file = file
        self.access = access
    }

    /// Loads the persisted device identity, generating and saving one on first use.
    public func current() -> DeviceIdentity {
        if let decoded = JSONStores.load(DeviceIdentity.self, from: file) {
            return decoded
        }
        let fresh = DeviceIdentity(
            deviceId: UUID().uuidString,
            os: "mac",
            hostname: Host.current().localizedName ?? ProcessInfo.processInfo.hostName,
            registeredAt: Date()
        )
        // Round-trip through encoder so the in-memory value has the same
        // date precision as the persisted JSON (ISO-8601 has second granularity).
        let data: Data
        let identity: DeviceIdentity
        do {
            data = try JSONStores.encoder().encode(fresh)
            identity = try JSONStores.decoder().decode(DeviceIdentity.self, from: data)
        } catch {
            FileHandle.standardError.write(
                Data("warning: device identity encode failed: \(error)\n".utf8))
            return fresh
        }
        guard access.allowsWrite else { return identity }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
        } catch {
            FileHandle.standardError.write(Data("warning: device identity persist failed: \(error)\n".utf8))
        }
        return identity
    }
}

/// Shared JSON coder configuration for the local stores (ISO-8601 dates, stable output).
enum JSONStores {
    static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }
    static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    /// Missing file → nil. Corrupt/unreadable file logs the error and returns nil.
    static func load<T: Decodable>(_ type: T.Type, from file: URL) -> T? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        do {
            let data = try Data(contentsOf: file)
            return try decoder().decode(type, from: data)
        } catch {
            FileHandle.standardError.write(
                Data("warning: failed to load \(file.lastPathComponent): \(error)\n".utf8))
            return nil
        }
    }
}
