import Foundation
import os

/// Device UUID files. Tests inject memory; production injects a disk adapter.
public protocol LicenseFileSystem: Sendable {
    func fileExists(at path: String) -> Bool
    func readUTF8(at path: String) throws -> String
    func writeUTF8(_ text: String, to path: String, posixPermissions: Int?) throws
    func createDirectory(at path: String) throws
    func listDirectory(at path: String) throws -> [String]
}

/// Path → UTF-8 map. No FileManager.
public final class MemoryLicenseFileSystem: LicenseFileSystem, Sendable {
    private struct Memory: Sendable {
        var files: [String: String] = [:]
        var directories: Set<String> = []
    }

    private let memory = OSAllocatedUnfairLock(initialState: Memory())

    public init() {}

    public func fileExists(at path: String) -> Bool {
        memory.withLock { $0.files[path] != nil }
    }

    public func readUTF8(at path: String) throws -> String {
        try memory.withLock { state in
            guard let text = state.files[path] else {
                throw DeviceUUIDRegistryError.missing(path)
            }
            return text
        }
    }

    public func writeUTF8(_ text: String, to path: String, posixPermissions: Int?) throws {
        _ = posixPermissions
        memory.withLock { state in
            state.files[path] = text
            state.directories.insert((path as NSString).deletingLastPathComponent)
        }
    }

    public func createDirectory(at path: String) throws {
        memory.withLock { state in
            _ = state.directories.insert(path)
        }
    }

    public func listDirectory(at path: String) throws -> [String] {
        memory.withLock { state in
            let prefix = path.hasSuffix("/") ? path : path + "/"
            return state.files.keys
                .filter { $0.hasPrefix(prefix) }
                .map { ($0 as NSString).lastPathComponent }
                .sorted()
        }
    }
}

/// Disk adapter — the only FileManager seam for device UUID files.
public struct DiskLicenseFileSystem: LicenseFileSystem {
    public init() {}

    public func fileExists(at path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    public func readUTF8(at path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    public func writeUTF8(_ text: String, to path: String, posixPermissions: Int?) throws {
        try text.write(toFile: path, atomically: true, encoding: .utf8)
        guard let mode = posixPermissions else { return }
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: path)
    }

    public func createDirectory(at path: String) throws {
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    }

    public func listDirectory(at path: String) throws -> [String] {
        guard FileManager.default.fileExists(atPath: path) else { return [] }
        return try FileManager.default.contentsOfDirectory(atPath: path)
    }
}
