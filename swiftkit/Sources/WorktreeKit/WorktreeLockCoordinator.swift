import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Git 락 경합(index.lock, refs lock 등) 감지기.
public enum WorktreeLockContentionDetector {
    private static let contentionMarkers: [String] = [
        "index.lock",
        "cannot lock ref",
        "another git process seems to be running",
        "unable to create",
        "is locked by another process",
        "resource temporarily unavailable",
        "is already locked"
    ]

    /// stderr 또는 오류 문자열이 Git 동시성 락 경합으로 인한 것인지 판별.
    public static func isLockContention(_ stderr: String) -> Bool {
        let lower = stderr.lowercased()
        // 'unable to create ... .lock' 또는 파일 존재 충돌 패턴
        if lower.contains("unable to create") && lower.contains(".lock") {
            return true
        }
        return contentionMarkers.contains { lower.contains($0) }
    }
}

/// 획득된 파일 락 핸들.
public struct WorktreeLockToken: Sendable {
    public let fd: Int32
    public let path: String

    public init(fd: Int32, path: String) {
        self.fd = fd
        self.path = path
    }
}

/// 다중 에이전트 및 다중 프로세스 간 워크트리 생성 락 코디네이터.
/// POSIX flock 기반 파일 락과 프로세스 내 직렬화 게이트를 결합하여 index.lock 경합을 방지.
public final class WorktreeLockCoordinator: Sendable {
    // 프로세스 내 동일 경로 락 요청을 직렬화하기 위한 액터 게이트
    private actor InProcessLockGate {
        private var lockedPaths: Set<String> = []
        private var waiters: [String: [CheckedContinuation<Void, Never>]] = [:]

        func lock(path: String) async {
            if !lockedPaths.contains(path) {
                lockedPaths.insert(path)
                return
            }
            await withCheckedContinuation { continuation in
                waiters[path, default: []].append(continuation)
            }
        }

        func unlock(path: String) {
            if var queue = waiters[path], !queue.isEmpty {
                let next = queue.removeFirst()
                waiters[path] = queue.isEmpty ? nil : queue
                next.resume()
            } else {
                lockedPaths.remove(path)
            }
        }
    }

    private let inProcessGate = InProcessLockGate()

    public static let defaultTimeout: TimeInterval = 30.0
    public static let defaultPollInterval: TimeInterval = 0.05

    public init() {}

    /// 파일 락 획득 후 작업 수행, 완료 시 자동 해제.
    public func withLock<T: Sendable>(
        lockPath: String,
        timeout: TimeInterval = defaultTimeout,
        operation: @Sendable () async throws -> T
    ) async throws -> T {
        // 1. 프로세스 내 직렬화
        await inProcessGate.lock(path: lockPath)
        defer {
            Task { await inProcessGate.unlock(path: lockPath) }
        }

        // 2. 프로세스 간 flock 획득
        let token = try await acquireFileLock(lockPath: lockPath, timeout: timeout)
        defer {
            releaseFileLock(token)
        }

        return try await operation()
    }

    /// flock 기반 파일 락 획득 (폴링 및 지터 백오프).
    public func acquireFileLock(
        lockPath: String,
        timeout: TimeInterval = defaultTimeout,
        pollInterval: TimeInterval = defaultPollInterval
    ) async throws -> WorktreeLockToken {
        ensureParentDirectory(for: lockPath)

        let start = Date()
        while true {
            guard let token = tryAcquireOnce(lockPath: lockPath) else {
                guard let fallbackToken = try await tryFallbackLockIfNeeded(
                    lockPath: lockPath,
                    timeout: timeout,
                    pollInterval: pollInterval
                ) else {
                    try checkTimeout(start: start, timeout: timeout, lockPath: lockPath)
                    await waitPollingInterval(pollInterval)
                    continue
                }
                return fallbackToken
            }
            return token
        }
    }

    private func tryFallbackLockIfNeeded(
        lockPath: String,
        timeout: TimeInterval,
        pollInterval: TimeInterval
    ) async throws -> WorktreeLockToken? {
        guard shouldFallback(errno: errno) else { return nil }
        let fallback = fallbackPath(for: lockPath)
        guard fallback != lockPath else { return nil }
        return try await acquireFileLock(lockPath: fallback, timeout: timeout, pollInterval: pollInterval)
    }

    private func checkTimeout(start: Date, timeout: TimeInterval, lockPath: String) throws {
        guard Date().timeIntervalSince(start) >= timeout else { return }
        guard !cleanupStaleLockIfDead(lockPath: lockPath) else { return }
        throw FastWorktreeError.lockTimeout(lockPath: lockPath, timeout: timeout)
    }

    private func ensureParentDirectory(for lockPath: String) {
        let parentDir = (lockPath as NSString).deletingLastPathComponent
        guard !FileManager.default.fileExists(atPath: parentDir) else { return }
        do {
            try FileManager.default.createDirectory(atPath: parentDir, withIntermediateDirectories: true)
        } catch {
            FileHandle.standardError.write(Data("WorktreeLock directory error: \(error)\n".utf8))
        }
    }

    private func tryAcquireOnce(lockPath: String) -> WorktreeLockToken? {
        #if canImport(Darwin)
        let fd = open(lockPath, O_RDWR | O_CREAT, 0o666)
        guard fd >= 0 else { return nil }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            close(fd)
            return nil
        }
        let pidString = "\(getpid())\n"
        ftruncate(fd, 0)
        pwrite(fd, pidString, pidString.utf8.count, 0)
        return WorktreeLockToken(fd: fd, path: lockPath)
        #else
        return WorktreeLockToken(fd: 0, path: lockPath)
        #endif
    }

    private func shouldFallback(errno: Int32) -> Bool {
        [EACCES, ENOENT, EROFS].contains(errno)
    }

    private func fallbackPath(for lockPath: String) -> String {
        let safeName = "worktree-lock-" + lockPath.replacingOccurrences(of: "/", with: "_")
        return FileManager.default.temporaryDirectory.appendingPathComponent(safeName).path
    }

    private func waitPollingInterval(_ pollInterval: TimeInterval) async {
        let jitter = Double.random(in: 0.01...0.04)
        let sleepTime = pollInterval + jitter
        do {
            try await Task.sleep(nanoseconds: UInt64(sleepTime * 1_000_000_000)) // lint:allow-sleep
        } catch is CancellationError {
            return
        } catch {
            return
        }
    }

    /// 파일 락 해제.
    public func releaseFileLock(_ token: WorktreeLockToken) {
        #if canImport(Darwin)
        guard token.fd >= 0 else { return }
        flock(token.fd, LOCK_UN)
        close(token.fd)
        #endif
    }

    /// 프로세스가 종료되어 버려진 부실 락 파일인지 검사하고 정리.
    private func cleanupStaleLockIfDead(lockPath: String) -> Bool {
        let content: String
        do {
            content = try String(contentsOfFile: lockPath, encoding: .utf8)
        } catch {
            return false
        }
        guard let pidInt = Int32(content.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return false
        }
        #if canImport(Darwin)
        guard kill(pidInt, 0) == -1, errno == ESRCH else { return false }
        do {
            try FileManager.default.removeItem(atPath: lockPath)
            return true
        } catch {
            return false
        }
        #else
        return false
        #endif
    }

    /// 락 경합 시 재시도 지수 백오프 시간 계산 (지터 포함).
    public static func backoffDelay(attempt: Int, baseDelay: TimeInterval) -> TimeInterval {
        let factor = pow(1.5, Double(max(0, attempt)))
        let jitter = Double.random(in: 0.02...0.06)
        return (baseDelay * factor) + jitter
    }
}
