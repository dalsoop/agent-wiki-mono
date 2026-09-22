import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// High-performance atomic file writer with in-memory directory caching,
/// change detection to skip redundant disk writes and fsyncs,
/// and crash-safe temporary file writing with atomic rename(2).
private final class DirectoryExistenceCache: Sendable {
    private let state = LockedState(Set<String>())

    func contains(_ dir: String) -> Bool {
        state.withLock { $0.contains(dir) }
    }

    func insert(_ dir: String) {
        _ = state.withLock { $0.insert(dir) }
    }

    func remove(_ dir: String) {
        _ = state.withLock { $0.remove(dir) }
    }

    func clear() {
        state.withLock { $0.removeAll(keepingCapacity: true) }
    }

    func ensureDirectoryExists(forFilePath filePath: String, force: Bool = false) throws {
        let parentDir = (filePath as NSString).deletingLastPathComponent
        guard !parentDir.isEmpty, parentDir != "." else { return }
        guard force || !contains(parentDir) else { return }

        var st = stat()
        let isDir = stat(parentDir, &st) == 0 && (st.st_mode & S_IFMT) == S_IFDIR
        if !isDir {
            try FileManager.default.createDirectory(atPath: parentDir, withIntermediateDirectories: true)
        }
        insert(parentDir)
    }
}

private let directoryCache = DirectoryExistenceCache()

/// High-performance atomic file writer with in-memory directory caching,
/// change detection to skip redundant disk writes and fsyncs,
/// and crash-safe temporary file writing with atomic rename(2).
public enum FastAtomicWriter: Sendable {
    /// Clears the directory existence in-memory cache.
    public static func clearDirectoryCache() {
        directoryCache.clear()
    }

    /// Writes data to a file atomically via a temporary file and `rename(2)`
    /// only if the destination file does not exist, differs in size, or has different content.
    ///
    /// If the file already exists and has identical size and bytes, the atomic write and fsync
    /// are skipped entirely, saving disk I/O.
    ///
    /// - Parameters:
    ///   - path: The target file path.
    ///   - data: The bytes to write.
    /// - Returns: `true` if file was written; `false` if skipped because content was identical.
    @discardableResult
    public static func writeIfChanged(to path: String, data: Data) throws -> Bool {
        var st = stat()
        guard stat(path, &st) == 0 else {
            try writeAtomic(to: path, data: data)
            return true
        }
        guard st.st_size == off_t(data.count) else {
            try writeAtomic(to: path, data: data)
            return true
        }
        guard !data.isEmpty else { return false }
        guard !isContentIdentical(path: path, size: data.count, data: data) else { return false }

        try writeAtomic(to: path, data: data)
        return true
    }

    /// Writes data to a URL atomically only if the file is new or modified.
    @discardableResult
    public static func writeIfChanged(to url: URL, data: Data) throws -> Bool {
        try writeIfChanged(to: url.path, data: data)
    }

    /// Writes string content to a file atomically only if the file is new or modified.
    @discardableResult
    public static func writeIfChanged(
        to path: String,
        string: String,
        encoding: String.Encoding = .utf8
    ) throws -> Bool {
        guard let data = string.data(using: encoding) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        return try writeIfChanged(to: path, data: data)
    }

    /// Writes string content to a URL atomically only if the file is new or modified.
    @discardableResult
    public static func writeIfChanged(
        to url: URL,
        string: String,
        encoding: String.Encoding = .utf8
    ) throws -> Bool {
        try writeIfChanged(to: url.path, string: string, encoding: encoding)
    }

    /// Unconditionally writes data to a file atomically using a temporary file in the same
    /// directory followed by `fsync` and `rename(2)` to prevent 0-byte corruption upon crashes.
    public static func writeAtomic(to path: String, data: Data) throws {
        let parentDir = (path as NSString).deletingLastPathComponent
        let dirForTemp = parentDir.isEmpty || parentDir == "." ? "." : parentDir
        let (fd, tempPath) = try openTemporaryFile(path: path, parentDir: parentDir, dirForTemp: dirForTemp)
        var activeFd: Int32 = fd

        var existingStat = stat()
        let existed = stat(path, &existingStat) == 0
        var writeSuccess = false
        defer {
            cleanupTemp(fd: activeFd, tempPath: tempPath, success: writeSuccess)
        }

        try writeBuffer(fd: activeFd, data: data)
        guard fsync(activeFd) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        if existed {
            fchmod(activeFd, existingStat.st_mode & 0o7777)
        }

        close(activeFd)
        activeFd = -1
        guard rename(tempPath, path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        writeSuccess = true
        syncDirectory(at: dirForTemp)
    }

    private static func cleanupTemp(fd: Int32, tempPath: String, success: Bool) {
        if fd >= 0 { close(fd) }
        if !success { unlink(tempPath) }
    }

    private static func openTemporaryFile(path: String, parentDir: String, dirForTemp: String) throws -> (fd: Int32, tempPath: String) {
        let filename = (path as NSString).lastPathComponent
        let tempPath = "\(dirForTemp)/.\(filename).tmp.\(UUID().uuidString)"
        try directoryCache.ensureDirectoryExists(forFilePath: path)

        var fd = open(tempPath, O_WRONLY | O_CREAT | O_TRUNC, 0o666)
        if fd < 0 && errno == ENOENT {
            directoryCache.remove(parentDir)
            try directoryCache.ensureDirectoryExists(forFilePath: path, force: true)
            fd = open(tempPath, O_WRONLY | O_CREAT | O_TRUNC, 0o666)
        }
        guard fd >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        return (fd, tempPath)
    }

    private static func writeBuffer(fd: Int32, data: Data) throws {
        guard !data.isEmpty else { return }
        try data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return }
            var written = 0
            let total = data.count
            while written < total {
                let n = write(fd, base.advanced(by: written), total - written)
                guard n >= 0 else {
                    guard errno == EINTR else {
                        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                    }
                    continue
                }
                written += n
            }
        }
    }

    private static func syncDirectory(at dir: String) {
        let parentFd = open(dir, O_RDONLY)
        guard parentFd >= 0 else { return }
        fsync(parentFd)
        close(parentFd)
    }

    /// Unconditionally writes data to a file atomically, applying explicit `permissions` on the
    /// destination file after rename. Use `0o600` for secret/credential files.
    ///
    /// If the file already exists, the original mode is preserved across rename, then overridden
    /// by `permissions` so callers don't need a separate `chmod` call (which has a TOCTOU race).
    public static func writeAtomic(to path: String, data: Data, permissions: mode_t) throws {
        try writeAtomic(to: path, data: data)
        chmod(path, permissions)
    }

    /// Atomically replaces destination file with an existing file (e.g. prepared SQLite or bundle archive)
    /// using `rename(2)` followed by parent directory `fsync` to flush directory entry metadata.
    public static func replaceAtomic(from tempPath: String, to destinationPath: String) throws {
        let parentDir = (destinationPath as NSString).deletingLastPathComponent
        let dirForParent = parentDir.isEmpty || parentDir == "." ? "." : parentDir
        guard rename(tempPath, destinationPath) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        syncDirectory(at: dirForParent)
    }

    /// Atomically replaces destination URL with an existing file URL using rename(2) and fsync.
    public static func replaceAtomic(from tempURL: URL, to destinationURL: URL) throws {
        try replaceAtomic(from: tempURL.path, to: destinationURL.path)
    }

    /// Unconditionally writes data to a URL atomically.
    public static func writeAtomic(to url: URL, data: Data) throws {
        try writeAtomic(to: url.path, data: data)
    }

    /// Unconditionally writes data to a URL atomically with explicit permissions.
    public static func writeAtomic(to url: URL, data: Data, permissions: mode_t) throws {
        try writeAtomic(to: url.path, data: data, permissions: permissions)
    }

    /// Unconditionally writes string content to a file atomically.
    public static func writeAtomic(
        to path: String,
        string: String,
        encoding: String.Encoding = .utf8
    ) throws {
        guard let data = string.data(using: encoding) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        try writeAtomic(to: path, data: data)
    }

    /// Unconditionally writes string content to a file atomically with explicit permissions.
    public static func writeAtomic(
        to path: String,
        string: String,
        encoding: String.Encoding = .utf8,
        permissions: mode_t
    ) throws {
        guard let data = string.data(using: encoding) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        try writeAtomic(to: path, data: data, permissions: permissions)
    }

    /// Unconditionally writes string content to a URL atomically.
    public static func writeAtomic(
        to url: URL,
        string: String,
        encoding: String.Encoding = .utf8
    ) throws {
        try writeAtomic(to: url.path, string: string, encoding: encoding)
    }

    /// Unconditionally writes string content to a URL atomically with explicit permissions.
    public static func writeAtomic(
        to url: URL,
        string: String,
        encoding: String.Encoding = .utf8,
        permissions: mode_t
    ) throws {
        try writeAtomic(to: url.path, string: string, encoding: encoding, permissions: permissions)
    }

    // MARK: - Internal Comparison

    private static func isContentIdentical(path: String, size: Int, data: Data) -> Bool {
        do {
            let mmap = try MmapBuffer(path: path)
            guard mmap.size == size else { return false }
            guard size > 0 else { return true }
            guard let ptr = mmap.pointer else { return false }
            return data.withUnsafeBytes { raw in
                guard let dataPtr = raw.baseAddress else { return false }
                return memcmp(ptr, dataPtr, size) == 0
            }
        } catch {
            return isContentIdenticalFallback(path: path, size: size, data: data)
        }
    }

    private static func isContentIdenticalFallback(path: String, size: Int, data: Data) -> Bool {
        let fd = open(path, O_RDONLY)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        return data.withUnsafeBytes { dataRawBuf in
            guard let base = dataRawBuf.baseAddress else { return false }
            var remaining = size
            var offset = 0
            var chunk = [UInt8](repeating: 0, count: min(64 * 1024, size))
            while remaining > 0 {
                let toRead = min(remaining, chunk.count)
                let bytesRead = read(fd, &chunk, toRead)
                guard bytesRead >= 0 else {
                    guard errno == EINTR else { return false }
                    continue
                }
                guard bytesRead == toRead else { return false }
                guard memcmp(base.advanced(by: offset), chunk, toRead) == 0 else { return false }
                offset += toRead
                remaining -= toRead
            }
            return true
        }
    }
}
