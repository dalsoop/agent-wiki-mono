import Foundation

extension FastStorageGC {

    static func processTemporaryEntry(
        _ entry: FastFileEntry,
        options: FastStorageGCOptions,
        report: inout FastStorageGCReport,
        fileManager: FileManager,
        now: Date
    ) {
        guard isTemporaryEntry(entry: entry, now: now, options: options) else { return }
        guard !options.dryRun else {
            report.prunedFiles.append(entry.path)
            report.reclaimedBytes += entry.size
            return
        }
        removeFile(at: entry.path, size: entry.size, report: &report, fileManager: fileManager)
    }

    static func findSessionCandidates(
        at rootPath: String,
        fileManager: FileManager
    ) throws -> [String] {
        let immediateDirs = try listImmediateDirectories(at: rootPath, fileManager: fileManager)
        var candidates: [String] = []
        for dir in immediateDirs {
            candidates.append(dir)
            let dirName = (dir as NSString).lastPathComponent
            guard isSessionContainerDirectory(name: dirName) else { continue }
            let nested = try listImmediateDirectories(at: dir, fileManager: fileManager)
            candidates.append(contentsOf: nested)
        }
        return candidates
    }

    static func isSessionContainerDirectory(name: String) -> Bool {
        sessionContainerNames.contains(name)
    }

    static func processSessionDirectory(
        _ dirPath: String,
        options: FastStorageGCOptions,
        report: inout FastStorageGCReport,
        fileManager: FileManager,
        now: Date
    ) {
        let name = (dirPath as NSString).lastPathComponent
        let dirMtime = fetchModificationDate(for: dirPath, fileManager: fileManager)
        let isOrphan = isOrphanSession(
            name: name,
            directoryPath: dirPath,
            dirMtime: dirMtime,
            now: now,
            options: options,
            fileManager: fileManager
        )
        guard isOrphan else { return }
        guard !options.dryRun else {
            let size = FastDirectorySizeCalculator.calculateSize(at: dirPath)
            report.prunedDirectories.append(dirPath)
            report.reclaimedBytes += Int64(clamping: size)
            return
        }
        removeDirectory(at: dirPath, report: &report, fileManager: fileManager)
    }

    static func pruneEmptyDirectoriesRecursively(
        at path: String,
        isRoot: Bool,
        dryRun: Bool,
        pruned: inout [String],
        errors: inout [String],
        fileManager: FileManager
    ) throws {
        let contents = try fileManager.contentsOfDirectory(atPath: path)
        for item in contents {
            let childPath = (path as NSString).appendingPathComponent(item)
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: childPath, isDirectory: &isDir), isDir.boolValue else {
                continue
            }
            try pruneEmptyDirectoriesRecursively(
                at: childPath,
                isRoot: false,
                dryRun: dryRun,
                pruned: &pruned,
                errors: &errors,
                fileManager: fileManager
            )
        }
        guard !isRoot else { return }
        let currentContents = try fileManager.contentsOfDirectory(atPath: path)
        guard currentContents.isEmpty else { return }
        pruned.append(path)
        guard !dryRun else { return }
        do {
            try fileManager.removeItem(atPath: path)
        } catch {
            errors.append("Failed to prune empty directory \(path): \(error.localizedDescription)")
        }
    }

    static func cleanupEmptyDirectoriesIfConfigured(
        rootPath: String,
        options: FastStorageGCOptions,
        report: inout FastStorageGCReport,
        fileManager: FileManager
    ) {
        guard options.removeEmptyDirectories else { return }
        do {
            let prunedEmpty = try pruneEmptyDirectories(at: rootPath, dryRun: options.dryRun, fileManager: fileManager)
            report.prunedDirectories.append(contentsOf: prunedEmpty)
        } catch {
            report.errors.append("Failed to prune empty directories at \(rootPath): \(error.localizedDescription)")
        }
    }

    static func mergeReports(
        into target: inout FastStorageGCReport,
        source: FastStorageGCReport
    ) {
        target.prunedFiles.append(contentsOf: source.prunedFiles)
        target.prunedDirectories.append(contentsOf: source.prunedDirectories)
        target.reclaimedBytes += source.reclaimedBytes
        target.errors.append(contentsOf: source.errors)
        target.scannedCount += source.scannedCount
    }

    static func removeFile(
        at path: String,
        size: Int64,
        report: inout FastStorageGCReport,
        fileManager: FileManager
    ) {
        do {
            try fileManager.removeItem(atPath: path)
            report.prunedFiles.append(path)
            report.reclaimedBytes += size
        } catch {
            report.errors.append("Failed to prune temporary file \(path): \(error.localizedDescription)")
        }
    }

    static func removeDirectory(
        at path: String,
        report: inout FastStorageGCReport,
        fileManager: FileManager
    ) {
        do {
            let size = FastDirectorySizeCalculator.calculateSize(at: path)
            try fileManager.removeItem(atPath: path)
            report.prunedDirectories.append(path)
            report.reclaimedBytes += Int64(clamping: size)
        } catch {
            report.errors.append("Failed to prune directory \(path): \(error.localizedDescription)")
        }
    }

    static func isTemporaryEntry(
        entry: FastFileEntry,
        now: Date,
        options: FastStorageGCOptions
    ) -> Bool {
        guard !entry.isDirectory else { return false }
        let isMatchingName = isTemporaryName(entry.name, options: options)
        let isInTempSubdir = isInsideTempDirectory(path: entry.path)
        guard isMatchingName || isInTempSubdir else { return false }
        let age = now.timeIntervalSince(entry.modifiedAt)
        return age >= options.maxTemporaryAge
    }

    static func isTemporaryName(
        _ name: String,
        options: FastStorageGCOptions
    ) -> Bool {
        guard !matchesExtension(name: name, extensions: options.temporaryExtensions) else { return true }
        return matchesPrefix(name: name, prefixes: options.temporaryPrefixes)
    }

    static func isInsideTempDirectory(path: String) -> Bool {
        let components = (path as NSString).pathComponents
        guard !components.contains("tmp") else { return true }
        guard !components.contains(".tmp") else { return true }
        return components.contains("cache")
    }

    static func matchesExtension(name: String, extensions: Set<String>) -> Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        guard !ext.isEmpty else { return false }
        return extensions.contains(ext)
    }

    static func matchesPrefix(name: String, prefixes: [String]) -> Bool {
        for prefix in prefixes {
            guard !name.hasPrefix(prefix) else { return true }
        }
        return false
    }

    static func isOrphanSession(
        name: String,
        directoryPath: String,
        dirMtime: Date,
        now: Date,
        options: FastStorageGCOptions,
        fileManager: FileManager
    ) -> Bool {
        guard matchesSessionPrefix(name: name, prefixes: options.sessionDirectoryPrefixes) else {
            return false
        }
        let pid = extractPID(fromDirectoryName: name) ?? readPIDFile(in: directoryPath, fileManager: fileManager)
        return evaluateOrphanStatus(pid: pid, dirMtime: dirMtime, now: now, options: options)
    }

    static func matchesSessionPrefix(name: String, prefixes: [String]) -> Bool {
        for prefix in prefixes {
            guard !name.hasPrefix(prefix) else { return true }
        }
        return false
    }

    static func evaluateOrphanStatus(
        pid: pid_t?,
        dirMtime: Date,
        now: Date,
        options: FastStorageGCOptions
    ) -> Bool {
        guard let pid else {
            return now.timeIntervalSince(dirMtime) >= options.maxOrphanSessionAge
        }
        guard let activePIDs = options.activePIDs else {
            return !isProcessAlive(pid)
        }
        return !activePIDs.contains(pid)
    }

    /// 디렉터리 이름의 마지막 대시 뒤 숫자로부터 PID 추출 (예: session-46040 -> 46040)
    public static func extractPID(fromDirectoryName name: String) -> pid_t? {
        let parts = name.split(separator: "-")
        guard let last = parts.last, let pidVal = Int32(last), pidVal > 0 else {
            return nil
        }
        return pidVal
    }

    static func readPIDFile(in dirPath: String, fileManager: FileManager) -> pid_t? {
        let pidPath = (dirPath as NSString).appendingPathComponent(".pid")
        guard fileManager.fileExists(atPath: pidPath) else { return nil }
        do {
            let content = try String(contentsOfFile: pidPath, encoding: .utf8)
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let val = Int32(trimmed), val > 0 else { return nil }
            return val
        } catch {
            return nil
        }
    }

    static func fetchModificationDate(for path: String, fileManager: FileManager) -> Date {
        do {
            let attrs = try fileManager.attributesOfItem(atPath: path)
            return (attrs[.modificationDate] as? Date) ?? Date.distantPast
        } catch {
            return Date.distantPast
        }
    }

    static func listImmediateDirectories(
        at path: String,
        fileManager: FileManager
    ) throws -> [String] {
        let items = try fileManager.contentsOfDirectory(atPath: path)
        var dirs: [String] = []
        for item in items {
            let fullPath = (path as NSString).appendingPathComponent(item)
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: fullPath, isDirectory: &isDir), isDir.boolValue else {
                continue
            }
            dirs.append(fullPath)
        }
        return dirs
    }
}
