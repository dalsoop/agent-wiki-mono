import Foundation

/// State of a local AI conversation/session lock on disk.
public enum SessionLockStatus: Sendable, Equatable {
    /// No lock file exists on disk, or it was safely unlocked.
    case unlocked
    /// Lock file is held by an actively running process (R, S, etc.).
    case active(pid: pid_t, command: String?)
    /// Lock file is held by a stopped/suspended process (STAT 'T', e.g. SIGTSTP / Ctrl+Z / SIGTTIN).
    /// This is a zombified/hanging session preventing reentry.
    case stopped(pid: pid_t, command: String?)
    /// Lock file exists on disk, but the owning process no longer exists (orphaned lock).
    case orphaned(lockPath: String)
}

/// Discovers, inspects, and auto-heals session locks for local AI CLIs.
public struct SessionLockProbe: Sendable {
    public init() {}

    /// Computes the standard lock file URL for a given runtime and session ID.
    public static func lockFileURL(
        runtime: AIRuntime,
        sessionID: String,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL? {
        switch runtime {
        case .agy:
            return home.appendingPathComponent(".gemini/antigravity-cli/presence/\(sessionID).lock")
        case .claude, .codex, .grok, .opencode, .cursor:
            return nil
        }
    }

    /// Inspects the lock state of a specific session.
    public func inspect(
        runtime: AIRuntime,
        sessionID: String,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) -> SessionLockStatus {
        guard let lockURL = Self.lockFileURL(runtime: runtime, sessionID: sessionID, home: home),
              fileManager.fileExists(atPath: lockURL.path) else {
            return .unlocked
        }

        guard let pid = findHoldingPID(for: lockURL.path) else {
            return .orphaned(lockPath: lockURL.path)
        }

        let (isAlive, isStopped, command) = queryProcess(pid: pid)
        guard isAlive else {
            return .orphaned(lockPath: lockURL.path)
        }
        if isStopped {
            return .stopped(pid: pid, command: command)
        }
        return .active(pid: pid, command: command)
    }

    /// Attempts to reclaim the lock if it is orphaned or held by a stopped process.
    /// Returns true if the lock is clean/reclaimed and ready for safe entry, false if actively locked.
    @discardableResult
    public func reclaimIfNeeded(
        runtime: AIRuntime,
        sessionID: String,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) -> Bool {
        let status = inspect(runtime: runtime, sessionID: sessionID, home: home, fileManager: fileManager)
        switch status {
        case .unlocked:
            return true
        case .orphaned(let path):
            return removeFileSilently(atPath: path, fileManager: fileManager)
        case .stopped(let pid, _):
            kill(pid, SIGKILL)
            guard let lockURL = Self.lockFileURL(runtime: runtime, sessionID: sessionID, home: home) else {
                return true
            }
            return removeFileSilently(atPath: lockURL.path, fileManager: fileManager)
        case .active:
            return false
        }
    }

    /// Scans presence directories across supported runtimes and removes all orphaned lock files.
    /// Returns the number of removed orphaned lock files.
    @discardableResult
    public func cleanAllOrphanedLocks(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) -> Int {
        cleanAgyLocks(home: home, fileManager: fileManager) +
        cleanClaudeLocks(home: home, fileManager: fileManager)
    }

    private func cleanAgyLocks(home: URL, fileManager: FileManager) -> Int {
        let dir = home.appendingPathComponent(".gemini/antigravity-cli/presence", isDirectory: true)
        guard let files = listDirectory(dir, fileManager: fileManager) else { return 0 }
        var count = 0
        for file in files where file.pathExtension == "lock" {
            guard findHoldingPID(for: file.path) == nil else { continue }
            if removeFileSilently(atPath: file.path, fileManager: fileManager) {
                count += 1
            }
        }
        return count
    }

    private func cleanClaudeLocks(home: URL, fileManager: FileManager) -> Int {
        let dir = home.appendingPathComponent(".claude/ide", isDirectory: true)
        guard let files = listDirectory(dir, fileManager: fileManager) else { return 0 }
        var count = 0
        for file in files where file.pathExtension == "lock" {
            if isClaudeLockOrphaned(file: file) && removeFileSilently(atPath: file.path, fileManager: fileManager) {
                count += 1
            }
        }
        return count
    }

    private func isClaudeLockOrphaned(file: URL) -> Bool {
        let pidStr = file.deletingPathExtension().lastPathComponent
        if let pid = Int32(pidStr) {
            let (isAlive, _, _) = queryProcess(pid: pid)
            return !isAlive
        }
        return findHoldingPID(for: file.path) == nil
    }

    private func listDirectory(_ dir: URL, fileManager: FileManager) -> [URL]? {
        do {
            return try fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        } catch {
            // Directory might not exist or be unreadable; return nil without failing
            return nil
        }
    }

    private func removeFileSilently(atPath path: String, fileManager: FileManager) -> Bool {
        do {
            try fileManager.removeItem(atPath: path)
            return true
        } catch {
            return false
        }
    }

    private func findHoldingPID(for path: String) -> pid_t? {
        guard let out = runWatchdogProcess(executable: "/usr/sbin/lsof", arguments: ["-n", "-P", "-t", path]),
              let firstLine = out.components(separatedBy: .newlines).first,
              let pid = Int32(firstLine.trimmingCharacters(in: .whitespaces)) else {
            return nil
        }
        return pid
    }

    private func queryProcess(pid: pid_t) -> (isAlive: Bool, isStopped: Bool, command: String?) {
        guard let out = runWatchdogProcess(executable: "/bin/ps", arguments: ["-o", "stat=,comm=", "-p", "\(pid)"]) else {
            return (false, false, nil)
        }
        let parts = out.split(separator: " ", maxSplits: 1).map(String.init)
        guard let stat = parts.first, !stat.isEmpty else {
            return (false, false, nil)
        }
        let comm = parts.count > 1 ? parts[1] : nil
        return (true, stat.contains("T"), comm)
    }

    private func runWatchdogProcess(executable: String, arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }

        // 워치독: 5초 타임아웃 초과 시 hang 방지를 위해 강제 terminate()
        let watchdog = Task { [weak process] in
            do {
                try await Task.sleep(nanoseconds: 5_000_000_000)
            } catch {
                return
            }
            guard let process, process.isRunning else { return }
            process.terminate()
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()

        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
