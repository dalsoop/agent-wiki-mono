import Foundation

/// One per-product device UUID. Directory name is the fleet SSOT.
public struct DeviceUUIDRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: String { service }
    public let service: String
    public let uuid: String

    public init(service: String, uuid: String) {
        self.service = service.trimmingCharacters(in: .whitespacesAndNewlines)
        self.uuid = uuid.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public enum DeviceUUIDRegistryError: Error, Equatable, Sendable {
    case emptyService
    case emptyUUID
    case missing(String)
}

/// Owns `net.ranode.license-devices`. Files: `<service-safe>.id`.
public struct DeviceUUIDRegistry: Sendable {
    public static let directoryName = "net.ranode.license-devices"

    private let files: any LicenseFileSystem
    private let root: URL

    public init(files: any LicenseFileSystem, root: URL) {
        self.files = files
        self.root = root
    }

    public static func defaultRoot(home: URL) -> URL {
        home
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(directoryName, isDirectory: true)
    }

    public func list() throws -> [DeviceUUIDRecord] {
        try files.createDirectory(at: root.path)
        let names = try files.listDirectory(at: root.path)
        return try names
            .filter { $0.hasSuffix(".id") }
            .compactMap { name in
                let path = root.appendingPathComponent(name).path
                let raw = try files.readUTF8(at: path)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !raw.isEmpty else { return nil }
                let service = String(name.dropLast(3))
                return DeviceUUIDRecord(service: service, uuid: raw)
            }
            .sorted { $0.service < $1.service }
    }

    public func get(service: String) throws -> DeviceUUIDRecord? {
        let needle = try requireService(service)
        let path = fileURL(for: needle).path
        guard files.fileExists(at: path) else { return nil }
        let uuid = try files.readUTF8(at: path)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !uuid.isEmpty else { return nil }
        return DeviceUUIDRecord(service: needle, uuid: uuid)
    }

    public func set(service: String, uuid: String) throws {
        let needle = try requireService(service)
        let value = uuid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw DeviceUUIDRegistryError.emptyUUID }
        try files.createDirectory(at: root.path)
        try files.writeUTF8(value, to: fileURL(for: needle).path, posixPermissions: 0o600)
    }

    private func requireService(_ service: String) throws -> String {
        let needle = service.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { throw DeviceUUIDRegistryError.emptyService }
        return needle
    }

    private func fileURL(for service: String) -> URL {
        root.appendingPathComponent("\(Self.safeFileName(service)).id")
    }

    public static func safeFileName(_ service: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        let mapped = service.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let name = String(mapped)
        return name.isEmpty ? "unknown" : name
    }
}
