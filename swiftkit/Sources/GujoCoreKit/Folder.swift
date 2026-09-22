import Foundation
import LocalizationKit

public struct Folder: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public var name: String
    public var path: String
    public let createdAt: Date
    public init(id: UUID = UUID(), name: String, path: String, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.path = path
        self.createdAt = createdAt
    }
}

public struct FolderError: Error, Sendable, Equatable { public let message: String }

public final class FolderStore: @unchecked Sendable {
    private let file: URL
    private let access: LedgerWriteAccess
    private var folders: [Folder]
    private let lock = NSLock()

    public init(file: URL = AppPaths.foldersFile, access: LedgerWriteAccess = .cloudApps) {
        self.file = file
        self.access = access
        folders = JSONStores.load([Folder].self, from: file) ?? []
    }

    public func all() -> [Folder] {
        lock.lock(); defer { lock.unlock() }
        return folders
    }

    @discardableResult
    public func add(name: String, path: String) throws -> Folder {
        let std = (path as NSString).standardizingPath
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: std, isDirectory: &isDir), isDir.boolValue else {
            throw FolderError(message: CLILocalization.format("Folder.message", std))
        }
        guard FileManager.default.isWritableFile(atPath: std) else {
            throw FolderError(message: CLILocalization.format("Folder.message-2", std))
        }
        lock.lock(); defer { lock.unlock() }
        if folders.contains(where: { ($0.path as NSString).standardizingPath == std }) {
            throw FolderError(message: CLILocalization.string("folder.error.already_registered"))
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let folder = Folder(name: trimmedName.isEmpty ? (std as NSString).lastPathComponent : trimmedName, path: std)
        folders.append(folder)
        try persist()
        return folder
    }

    @discardableResult
    public func ensure(name: String, path: String) throws -> Folder {
        let std = (path as NSString).standardizingPath
        lock.lock()
        if let existing = folders.first(where: { ($0.path as NSString).standardizingPath == std }) {
            lock.unlock()
            return existing
        }
        lock.unlock()
        try FileManager.default.createDirectory(atPath: std, withIntermediateDirectories: true)
        return try add(name: name, path: std)
    }

    public func rename(id: UUID, to name: String) throws {
        lock.lock(); defer { lock.unlock() }
        guard let i = folders.firstIndex(where: { $0.id == id }) else {
            throw FolderError(message: CLILocalization.string("folder.error.not_found"))
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        folders[i].name = trimmed.isEmpty ? (folders[i].path as NSString).lastPathComponent : trimmed
        try persist()
    }

    public func remove(id: UUID) throws {
        lock.lock(); defer { lock.unlock() }
        folders.removeAll { $0.id == id }
        try persist()
    }

    private func persist() throws {
        guard access.allowsWrite else { throw LedgerWriteDenied.retiredOwner }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONStores.encoder().encode(folders).write(to: file, options: .atomic)
    }
}
