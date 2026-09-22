
private enum UnzipTool {
    static let path = "/usr/bin/unzip"
    static let waitSeconds: TimeInterval = 30
}

import Foundation
import CryptoKit
import CommandKit

public struct DownloadError: Error, LocalizedError, Sendable {
    public let message: String
    public init(message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public struct DownloadEngine: Sendable {
    public init() {}

    public func sha256Hex(of file: URL) throws -> String {
        let data = try Data(contentsOf: file)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Unzips `zip` into `dest` (created if needed) using /usr/bin/unzip. Atomic-ish: extracts into a
    /// temp sibling then moves into place.
    public func unzip(_ zip: URL, into dest: URL) async throws {
        guard FileManager.default.fileExists(atPath: zip.path) else {
            throw DownloadError(message: "zip not found: \(zip.path)")
        }
        try await validateZipEntries(zip)
        let staging = dest.deletingLastPathComponent()
            .appendingPathComponent(".unzip-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)

        do {
            try await runUnzip(zip, into: staging)
            try validateExtractedTree(staging)
            try replaceDirectory(at: dest, with: staging)
        } catch {
            do {
                try FileManager.default.removeItem(at: staging)
            } catch {
                FileHandle.standardError.write(Data("warning: unzip staging cleanup failed: \(error)\n".utf8))
            }
            throw error
        }
    }

    private func runUnzip(_ zip: URL, into staging: URL) async throws {
        let result = await ProcessCommandRunner().run(
            UnzipTool.path,
            ["-o", "-q", zip.path, "-d", staging.path],
            timeout: UnzipTool.waitSeconds
        )
        guard result.ok else {
            throw DownloadError(message: "unzip failed (\(result.exitCode)): \(result.stderr)")
        }
    }

    private func validateZipEntries(_ zip: URL) async throws {
        let result = await ProcessCommandRunner().run(
            UnzipTool.path,
            ["-Z1", zip.path],
            timeout: UnzipTool.waitSeconds
        )
        guard result.ok else {
            throw DownloadError(message: "zip listing failed (\(result.exitCode)): \(result.stderr)")
        }
        let listing = result.stdout
        for raw in listing.split(separator: "\n", omittingEmptySubsequences: true) {
            let entry = String(raw)
            let parts = entry.split(separator: "/", omittingEmptySubsequences: false)
            if entry.hasPrefix("/") || parts.contains("..") {
                throw DownloadError(message: "unsafe zip entry: \(entry)")
            }
        }
    }

    private func validateExtractedTree(_ root: URL) throws {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let rootStd = root.standardizedFileURL
        let rootPath = rootStd.path.hasSuffix("/") ? rootStd.path : rootStd.path + "/"
        let fm = FileManager.default
        for case let url as URL in enumerator {
            // Non-symlink paths are already confined by unzip destination; still reject escapes.
            guard url.standardizedFileURL.path.hasPrefix(rootPath)
                    || url.standardizedFileURL.path == rootStd.path else {
                throw DownloadError(message: "unsafe extracted path: \(url.path)")
            }
            let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard values.isSymbolicLink ?? false else { continue }
            // macOS .app / .framework trees use relative versioned symlinks
            // (Resources → Versions/Current/Resources). Allow only destinations that
            // resolve inside the extract root; reject absolute / escaping links.
            let dest = try fm.destinationOfSymbolicLink(atPath: url.path)
            if dest.hasPrefix("/") {
                throw DownloadError(message: "unsafe absolute symlink in bundle: \(url.lastPathComponent) → \(dest)")
            }
            let resolved = url.deletingLastPathComponent().appendingPathComponent(dest).standardizedFileURL
            let resolvedPath = resolved.path
            guard resolvedPath == rootStd.path || resolvedPath.hasPrefix(rootPath) else {
                throw DownloadError(message: "unsafe symlink escape in bundle: \(url.lastPathComponent) → \(dest)")
            }
        }
    }

    private func replaceDirectory(at dest: URL, with staging: URL) throws {
        try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        let backup = dest.deletingLastPathComponent()
            .appendingPathComponent(".backup-\(dest.lastPathComponent)-\(UUID().uuidString)", isDirectory: true)
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.moveItem(at: dest, to: backup)
        }
        do {
            try FileManager.default.moveItem(at: staging, to: dest)
            if FileManager.default.fileExists(atPath: backup.path) {
                do {
                    try FileManager.default.removeItem(at: backup)
                } catch {
                    FileHandle.standardError.write(Data("warning: unzip backup cleanup failed: \(error)\n".utf8))
                }
            }
        } catch {
            if FileManager.default.fileExists(atPath: backup.path),
               !FileManager.default.fileExists(atPath: dest.path) {
                do {
                    try FileManager.default.moveItem(at: backup, to: dest)
                } catch {
                    FileHandle.standardError.write(Data("warning: unzip dest restore failed: \(error)\n".utf8))
                }
            }
            throw error
        }
    }
}
