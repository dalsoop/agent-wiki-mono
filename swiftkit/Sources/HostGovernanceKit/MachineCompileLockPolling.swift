import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// 커널 `flock(2)` 기반 분산 프로세스 상호 배제 컴파일 락.
///
/// 설계 보장:
/// 1. Open File Table Description 기반: 프로세스 크래시/SIGKILL 시 OS 커널이 디스크립터를 정리하며 락 100% 자동 해제 (Deadlock 불가).
/// 2. Non-blocking `LOCK_NB` 선행 시도로 즉시 경합 감지.
/// 3. 자가 치유(Self-healing): 이전 프로세스가 남긴 잔여 락 파일이 존재해도 커널 락 소유권이 없으면 즉시 획득.
public final class MachineCompileLock: Sendable {
    public static let shared = MachineCompileLock()

    private let lockFileURL: URL

    public init(lockDir: URL? = nil) {
        let defaultDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("swift-mono-governance")
        let dir = lockDir ?? defaultDir
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            _ = error
        }
        self.lockFileURL = dir.appendingPathComponent("machine-compile.lock")
    }

    public enum LockError: Error, LocalizedError, Sendable {
        case openFailed(String)
        case lockFailed(String)
        case timedOut(TimeInterval)

        public var errorDescription: String? {
            switch self {
            case .openFailed(let msg): return "Failed to open compile lock file: \(msg)"
            case .lockFailed(let msg): return "Failed to acquire compile lock: \(msg)"
            case .timedOut(let s): return "Timed out waiting for compile lock after \(s) seconds"
            }
        }
    }

    /// 배타 락을 획득하고 작업을 실행한 뒤 락을 해제한다 (동기 블로킹).
    public func withLock<T: Sendable>(
        timeout: TimeInterval = 60.0,
        _ operation: () throws -> T
    ) throws -> T {
        let fd = openLockFile()
        guard fd >= 0 else {
            throw LockError.openFailed(String(cString: strerror(errno)))
        }
        defer { close(fd) }

        try acquireKernelLockSync(fd: fd)
        defer { releaseKernelLock(fd: fd) }

        return try operation()
    }

    /// 비동기 지원 오버로드 (Task.sleep 기반 논블로킹 폴링).
    public func withLock<T: Sendable>(
        timeout: TimeInterval = 60.0,
        _ operation: () async throws -> T
    ) async throws -> T {
        let fd = openLockFile()
        guard fd >= 0 else {
            throw LockError.openFailed(String(cString: strerror(errno)))
        }
        defer { close(fd) }

        try await acquireKernelLockAsync(fd: fd, timeout: timeout)
        defer { releaseKernelLock(fd: fd) }

        return try await operation()
    }

    private func openLockFile() -> Int32 {
        let path = lockFileURL.path
        return open(path, O_RDWR | O_CREAT, 0o644)
    }

    private func acquireKernelLockSync(fd: Int32) throws {
        // 커널 블로킹 flock: 다른 프로세스가 release 할 때까지 커널 컨텍스트 전환 대기
        guard flock(fd, LOCK_EX) == 0 else {
            throw LockError.lockFailed(String(cString: strerror(errno)))
        }
    }

    private func acquireKernelLockAsync(fd: Int32, timeout: TimeInterval) async throws {
        // 1. Non-blocking 시도
        if flock(fd, LOCK_EX | LOCK_NB) == 0 {
            return
        }

        // 2. 경합 시 Task.sleep 비동기 폴링 대기
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            try await Task.sleep(nanoseconds: 50_000_000) // 50ms
            if flock(fd, LOCK_EX | LOCK_NB) == 0 {
                return
            }
        }

        throw LockError.timedOut(timeout)
    }

    private func releaseKernelLock(fd: Int32) {
        _ = flock(fd, LOCK_UN)
    }
}
