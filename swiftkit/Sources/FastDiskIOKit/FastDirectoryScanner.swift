import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public enum FastDirectoryScanner: Sendable {
    public static let defaultSkipping: Set<String> = [
        ".git",
        ".build",
        ".bare",
        "node_modules",
        "DerivedData",
    ]

    nonisolated(unsafe) public static var onOperationCompleted: (@Sendable (String, TimeInterval) -> Void)?

    public static func scan(
        root: String,
        recursive: Bool = true,
        skipping: Set<String> = defaultSkipping,
        skipsPackageDescendants: Bool = false
    ) throws -> [FastFileEntry] {
        let start = Date().timeIntervalSinceReferenceDate
        defer {
            let elapsed = Date().timeIntervalSinceReferenceDate - start
            onOperationCompleted?("FastDirectoryScanner", elapsed)
        }
        var results = [FastFileEntry]()
        try traverse(root: root, recursive: recursive, skipping: skipping, skipsPackageDescendants: skipsPackageDescendants) { entry in
            results.append(entry)
            return true
        }
        return results
    }

    public static func scanEntries(
        in path: String,
        recursive: Bool = true,
        skipping: Set<String> = defaultSkipping,
        skipsPackageDescendants: Bool = false
    ) -> [FastFileEntry] {
        do {
            return try scan(root: path, recursive: recursive, skipping: skipping, skipsPackageDescendants: skipsPackageDescendants)
        } catch {
            return []
        }
    }

    /// Returns all non-directory file paths under the specified root path.
    public static func allFiles(
        under rootPath: String,
        recursive: Bool = true,
        skipping: Set<String> = defaultSkipping
    ) -> [String] {
        scanEntries(in: rootPath, recursive: recursive, skipping: skipping)
            .filter { !$0.isDirectory }
            .map(\.path)
    }

    /// Returns all non-directory file URLs under the specified root URL.
    public static func allFiles(
        under root: URL,
        recursive: Bool = true,
        skipping: Set<String> = defaultSkipping
    ) -> [URL] {
        allFiles(under: root.path, recursive: recursive, skipping: skipping)
            .map { URL(fileURLWithPath: $0) }
    }

    /// Enumerates non-directory files under the root path, invoking the handler for each file entry.
    public static func enumerateFiles(
        at rootPath: String,
        recursive: Bool = true,
        skipping: Set<String> = defaultSkipping,
        handler: (FastFileEntry) throws -> Void
    ) rethrows {
        for entry in scanEntries(in: rootPath, recursive: recursive, skipping: skipping) {
            guard !entry.isDirectory else { continue }
            try handler(entry)
        }
    }

    /// Enumerates non-directory files under the root URL, invoking the handler for each file entry.
    public static func enumerateFiles(
        at root: URL,
        recursive: Bool = true,
        skipping: Set<String> = defaultSkipping,
        handler: (FastFileEntry) throws -> Void
    ) rethrows {
        try enumerateFiles(at: root.path, recursive: recursive, skipping: skipping, handler: handler)
    }


    public static func stream(
        root: String,
        recursive: Bool = true,
        skipping: Set<String> = defaultSkipping
    ) -> AsyncStream<FastFileEntry> {
        AsyncStream { continuation in
            Task.detached(priority: .utility) {
                do {
                    _ = try traverse(root: root, recursive: recursive, skipping: skipping) { entry in
                        continuation.yield(entry)
                        return true
                    }
                } catch {
                    continuation.finish()
                    return
                }
                continuation.finish()
            }
        }
    }

    @discardableResult
    private static func traverse(
        root: String,
        recursive: Bool,
        skipping: Set<String>,
        skipsPackageDescendants: Bool = false,
        yield: (FastFileEntry) -> Bool
    ) throws -> Bool {
        var rootStat = stat()
        guard lstat(root, &rootStat) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .ENOENT)
        }

        guard (rootStat.st_mode & S_IFMT) == S_IFDIR else {
            let name = (root as NSString).lastPathComponent
            _ = yield(makeEntry(path: root, name: name, st: rootStat))
            return true
        }

        var dirQueue = [root]
        while let currentDir = dirQueue.popLast() {
            let shouldContinue = scanDirectory(
                currentDir,
                recursive: recursive,
                skipping: skipping,
                skipsPackageDescendants: skipsPackageDescendants,
                queue: &dirQueue,
                yield: yield
            )
            guard shouldContinue else { return false }
        }
        return true
    }

    private static func scanDirectory(
        _ currentDir: String,
        recursive: Bool,
        skipping: Set<String>,
        skipsPackageDescendants: Bool,
        queue: inout [String],
        yield: (FastFileEntry) -> Bool
    ) -> Bool {
        guard let dir = opendir(currentDir) else { return true }
        defer { closedir(dir) }
        let dfd = dirfd(dir)

        while let entryPtr = readdir(dir) {
            guard let name = parseEntryName(entryPtr, skipping: skipping) else { continue }
            let childPath = currentDir.hasSuffix("/") ? "\(currentDir)\(name)" : "\(currentDir)/\(name)"
            guard let st = readStat(dfd: dfd, name: name, childPath: childPath) else { continue }

            let fileEntry = makeEntry(path: childPath, name: name, st: st)
            guard yield(fileEntry) else { return false }

            let isDirectory = (st.st_mode & S_IFMT) == S_IFDIR
            if recursive && isDirectory {
                let isPackageBundle = [".app", ".framework", ".bundle"].contains(where: { name.hasSuffix($0) })
                if skipsPackageDescendants && isPackageBundle {
                    // Skip descending into package bundles
                } else {
                    queue.append(childPath)
                }
            }
        }
        return true
    }

    private static func parseEntryName(
        _ entryPtr: UnsafeMutablePointer<dirent>,
        skipping: Set<String>
    ) -> String? {
        let name = POSIXCompat.direntName(entryPtr)
        guard name != "." && name != ".." else { return nil }
        guard !skipping.contains(name) else { return nil }
        return name
    }

    private static func readStat(dfd: Int32, name: String, childPath: String) -> stat? {
        var st = stat()
        let result = dfd >= 0 ? fstatat(dfd, name, &st, AT_SYMLINK_NOFOLLOW) : lstat(childPath, &st)
        guard result == 0 || lstat(childPath, &st) == 0 else { return nil }
        return st
    }

    private static func makeEntry(path: String, name: String, st: stat) -> FastFileEntry {
        let isDir = (st.st_mode & S_IFMT) == S_IFDIR
        let mtimeSec = Double(POSIXCompat.mtimeSec(st))
        let mtimeNsec = Double(POSIXCompat.mtimeNsec(st))
        let modifiedAt = Date(timeIntervalSince1970: mtimeSec + (mtimeNsec / 1_000_000_000.0))
        return FastFileEntry(
            path: path,
            name: name,
            size: Int64(st.st_size),
            modifiedAt: modifiedAt,
            isDirectory: isDir,
            inode: UInt64(st.st_ino),
            device: UInt64(st.st_dev)
        )
    }
}
