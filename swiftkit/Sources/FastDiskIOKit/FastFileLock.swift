import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// FastFileLock — OS 커널 레벨 파일 락(flock)의 단일 진실의 원천(SSOT).
///
/// 모노레포 전역에서 제각각 구현되던 사설 flock(open/O_CREAT/LOCK_EX/LOCK_SH/LOCK_NB)을
/// 단일 표준으로 통합하여 다음 문제를 영구 차단한다:
/// 1. fd 누수 (defer 누락으로 프로세스 종료 전까지 락이 반환되지 않음)
/// 2. 부모 디렉터리 부재 시 open 실패로 무방비 동시 실행
/// 3. non-blocking 실패 시 fd 미정리(close 누락)
/// 4. 크래시 시 커널이 fd를 닫으며 자동 해제되는 flock의 안전성 보장
public final class FastFileLock: Sendable {
    public let url: URL
    private let fdState = LockedState<Int32>(-1)

    public init(url: URL) {
        self.url = url
    }

    public var isHeld: Bool {
        fdState.withLock { $0 >= 0 }
    }

    public var fileDescriptor: Int32 {
        fdState.withLock { $0 }
    }

    /// 파일 락을 획득한다.
    /// - Parameters:
    ///   - exclusive: true면 배타적 락(LOCK_EX), false면 공유 락(LOCK_SH). 기본값 true.
    ///   - nonBlocking: true면 즉시 반환(LOCK_NB), 이미 잠겨있으면 false 반환.
    /// - Returns: 락 획득 성공 여부
    @discardableResult
    public func acquire(exclusive: Bool = true, nonBlocking: Bool = false) -> Bool {
        return fdState.withLock { currentFd in
            guard currentFd < 0 else { return true } // 이미 소유 중

            let dir = url.deletingLastPathComponent()
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            } catch {
                return false
            }

            let descriptor = open(url.path, O_CREAT | O_RDWR, 0o644)
            guard descriptor >= 0 else { return false }

            var flags = exclusive ? LOCK_EX : LOCK_SH
            if nonBlocking {
                flags |= LOCK_NB
            }

            if flock(descriptor, flags) != 0 {
                close(descriptor)
                return false
            }

            currentFd = descriptor
            return true
        }
    }

    /// 파일 락을 해제하고 디스크립터를 닫는다.
    public func release() {
        fdState.withLock { currentFd in
            guard currentFd >= 0 else { return }
            flock(currentFd, LOCK_UN)
            close(currentFd)
            currentFd = -1
        }
    }

    /// 기존 파일 디스크립터에 락을 설정한다.
    @discardableResult
    public static func lock(descriptor: Int32, exclusive: Bool = true, nonBlocking: Bool = false) -> Bool {
        var flags = exclusive ? LOCK_EX : LOCK_SH
        if nonBlocking {
            flags |= LOCK_NB
        }
        return flock(descriptor, flags) == 0
    }

    /// 파일 디스크립터의 락을 해제한다.
    @discardableResult
    public static func unlock(descriptor: Int32) -> Bool {
        return flock(descriptor, LOCK_UN) == 0
    }

    deinit {
        release()
    }

    // MARK: - Static Convenience Helpers

    /// 지정된 파일 경로에 락을 걸고 클로저를 실행한다 (Blocking).
    /// - Parameters:
    ///   - url: 락 파일 URL
    ///   - exclusive: 배타적 락 여부 (기본 true)
    ///   - body: 락 소유 중 실행할 작업
    @discardableResult
    public static func withLock<T>(
        at url: URL,
        exclusive: Bool = true,
        _ body: () throws -> T
    ) throws -> T {
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let descriptor = open(url.path, O_CREAT | O_RDWR, 0o644)
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { close(descriptor) }

        guard flock(descriptor, exclusive ? LOCK_EX : LOCK_SH) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { flock(descriptor, LOCK_UN) }

        return try body()
    }

    /// 지정된 파일 경로에 non-blocking 락을 시도하고, 획득 시 클로저를 실행한다.
    /// 다른 프로세스가 이미 락을 쥐고 있으면 nil을 반환한다.
    public static func tryWithLock<T>(
        at url: URL,
        exclusive: Bool = true,
        _ body: () throws -> T
    ) throws -> T? {
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let descriptor = open(url.path, O_CREAT | O_RDWR, 0o644)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }

        let flags = (exclusive ? LOCK_EX : LOCK_SH) | LOCK_NB
        guard flock(descriptor, flags) == 0 else {
            return nil
        }
        defer { flock(descriptor, LOCK_UN) }

        return try body()
    }

    /// 타깃 파일 주변에 `.lock` 확장자를 붙여 배타적 락을 수행한다.
    @discardableResult
    public static func exclusive<T>(
        around targetURL: URL,
        _ body: () throws -> T
    ) throws -> T {
        let lockURL = targetURL.appendingPathExtension("lock")
        return try withLock(at: lockURL, exclusive: true, body)
    }
}

/// FastProcessLock — PID 기반 단일 인스턴스/프로세스 상호 배제 락 SSOT.
///
/// 데몬, LaunchAgent, 워크플로 엔진 등에서 복사-붙여넣기되던 원시 C `flock(fd, LOCK_EX | LOCK_NB)` 및
/// PID 기록/점유자 확인 패턴을 안전하게 추상화한다.
public final class FastProcessLock: Sendable {
    public let url: URL
    private let state = LockedState<(fd: Int32, pid: pid_t)>((-1, 0))

    public init(url: URL) {
        self.url = url
    }

    public var isHeld: Bool {
        state.withLock { $0.fd >= 0 }
    }

    /// 논블로킹으로 프로세스 락을 획득하고 현재 프로세스의 PID를 기록한다.
    /// 이미 다른 프로세스가 소유 중이면 false를 반환한다.
    public func tryAcquire() -> Bool {
        return state.withLock { current in
            guard current.fd < 0 else { return true }
            let dir = url.deletingLastPathComponent()
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            } catch {
                return false
            }

            let fd = open(url.path, O_CREAT | O_RDWR, 0o644)
            guard fd >= 0 else { return false }

            guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
                close(fd)
                return false
            }

            ftruncate(fd, 0)
            let pidStr = "\(getpid())\n"
            _ = pidStr.withCString { write(fd, $0, strlen($0)) }
            _ = fsync(fd)

            current = (fd, getpid())
            return true
        }
    }

    /// 현재 락을 소유하고 있는 프로세스의 PID를 읽는다 (락을 점유하지 않은 상태에서 조회 가능).
    public func currentHolderPID() -> pid_t? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pid = pid_t(trimmed), pid > 0 else { return nil }
        return pid
    }

    /// 락을 해제하고 디스크립터를 닫는다.
    public func release() {
        state.withLock { current in
            guard current.fd >= 0 else { return }
            ftruncate(current.fd, 0)
            flock(current.fd, LOCK_UN)
            close(current.fd)
            current = (-1, 0)
        }
    }

    deinit {
        release()
    }
}
