import Foundation
#if canImport(os)
import os
#endif
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// 락 획득 실패 및 파일 관련 오류.
public enum InstallLockError: Error, LocalizedError, Sendable, Equatable {
    case timeout(slug: String, seconds: TimeInterval)
    case fileOpenFailed(path: String, errno: Int32)
    case lockFailed(slug: String, errno: Int32)

    public var errorDescription: String? {
        switch self {
        case .timeout(let slug, let seconds):
            return "install-lock: '\(slug)' 락 대기 시간 초과 (\(Int(seconds))초)"
        case .fileOpenFailed(let path, let errno):
            return "install-lock: 락 파일 생성/열기 실패 (\(path), errno=\(errno))"
        case .lockFailed(let slug, let errno):
            return "install-lock: '\(slug)' 락 획득 실패 (errno=\(errno))"
        }
    }
}

/// install-cli 동시 실행 시 POSIX 파일 락(`flock`)으로 중복 빌드를 차단한다.
///
/// 같은 CLI 를 여러 세션(claude/codex/grok)이 동시에 설치하면 CPU·시간이 N배다.
/// POSIX `flock(LOCK_EX)` 로 per-slug 배타 락을 잡아 첫 세션만 빌드하고,
/// 나머지는 락 대기 후 캐시를 재확인해 스킵한다.
///
/// 락 파일 경로: `/tmp/gujo-install-<slug>.lock`
/// 프로세스가 크래시하면 OS 커널이 fd를 닫으며 `flock`이 자동 해제된다.
public enum InstallLock {

    /// 락 파일 기본 디렉터리 (하위호환용).
    public static var lockDirectory: URL {
        URL(fileURLWithPath: "/tmp", isDirectory: true)
    }

    /// slug에 해당하는 락 파일의 절대 경로를 반환한다: `/tmp/gujo-install-<slug>.lock`
    public static func lockPath(slug: String) -> String {
        let safeSlug = slug.replacingOccurrences(of: "/", with: "-")
        return "/tmp/gujo-install-\(safeSlug).lock"
    }

    /// RAII 스타일 Lock 토큰.
    /// 스코프를 벗어나 deinit 되거나 `unlock()` 명시 호출 시 fd가 닫히고 POSIX flock 이 안전하게 해제된다.
    public final class Token: Sendable {
        public let slug: String
        public let path: String
        private let fd: Int32
        #if canImport(os)
        private let isReleasedLock: OSAllocatedUnfairLock<Bool>
        #else
        private let isReleasedLock: NSLock
        private nonisolated(unsafe) var _isReleased: Bool = false
        #endif

        init(slug: String, path: String, fd: Int32) {
            self.slug = slug
            self.path = path
            self.fd = fd
            #if canImport(os)
            self.isReleasedLock = OSAllocatedUnfairLock(initialState: false)
            #else
            self.isReleasedLock = NSLock()
            self._isReleased = false
            #endif
        }

        deinit {
            unlock()
        }

        public func unlock() {
            #if canImport(os)
            isReleasedLock.withLock { released in
                guard !released else { return }
                released = true
                flock(fd, LOCK_UN)
                close(fd)
            }
            #else
            isReleasedLock.lock()
            defer { isReleasedLock.unlock() }
            guard !_isReleased else { return }
            _isReleased = true
            flock(fd, LOCK_UN)
            close(fd)
            #endif
        }
    }

    /// per-slug 배타 락을 획득한다.
    ///
    /// - Parameters:
    ///   - slug: 대상 식별자 (락 경로: `/tmp/gujo-install-<slug>.lock`)
    ///   - timeoutSeconds: 락 획득 대기 최대 시간(초). 0 이하이면 논블로킹(즉시 시도).
    /// - Returns: 획득 성공 시 RAII 토큰 (`Token`), 타임아웃 시 `nil`.
    public static func acquire(slug: String, timeoutSeconds: TimeInterval = 0) throws -> Token? {
        let path = lockPath(slug: slug)
        var fd = open(path, O_RDWR | O_CREAT, 0o644)
        if fd < 0 {
            fd = open(path, O_RDONLY | O_CREAT, 0o644)
        }
        guard fd >= 0 else {
            throw InstallLockError.fileOpenFailed(path: path, errno: errno)
        }

        if timeoutSeconds <= 0 {
            if flock(fd, LOCK_EX | LOCK_NB) == 0 {
                return Token(slug: slug, path: path, fd: fd)
            }
            let err = errno
            close(fd)
            if err == EWOULDBLOCK || err == EAGAIN {
                return nil
            }
            throw InstallLockError.lockFailed(slug: slug, errno: err)
        }

        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while true {
            if flock(fd, LOCK_EX | LOCK_NB) == 0 {
                return Token(slug: slug, path: path, fd: fd)
            }
            let err = errno
            if err != EWOULDBLOCK && err != EAGAIN {
                close(fd)
                throw InstallLockError.lockFailed(slug: slug, errno: err)
            }
            if Date() >= deadline {
                close(fd)
                return nil
            }
            var req = timespec(tv_sec: 0, tv_nsec: 50_000_000)
            nanosleep(&req, nil)
        }
    }

    /// per-slug 배타 락을 잡고 동기 `action`을 실행한다.
    ///
    /// - Parameters:
    ///   - slug: 대상 식별자 (락 경로: `/tmp/gujo-install-<slug>.lock`)
    ///   - timeoutSeconds: 락 획득 대기 최대 시간(초). 기본값 600초.
    ///   - action: 락 안에서 실행할 클로저
    /// - Returns: `action`의 반환값
    @discardableResult
    public static func withLock<T>(
        slug: String,
        timeoutSeconds: TimeInterval = 600,
        action: () throws -> T
    ) throws -> T {
        guard let token = try acquire(slug: slug, timeoutSeconds: timeoutSeconds) else {
            throw InstallLockError.timeout(slug: slug, seconds: timeoutSeconds)
        }
        defer { token.unlock() }
        return try action()
    }

    /// per-slug 배타 락을 잡고 비동기 `action`을 실행한다.
    @discardableResult
    public static func withLock<T>(
        slug: String,
        timeoutSeconds: TimeInterval = 600,
        action: () async throws -> T
    ) async throws -> T {
        guard let token = try acquire(slug: slug, timeoutSeconds: timeoutSeconds) else {
            throw InstallLockError.timeout(slug: slug, seconds: timeoutSeconds)
        }
        defer { token.unlock() }
        return try await action()
    }

    /// 하위호환을 위한 기존 시그니처 지원: `cli` 이름으로 호출하고 경고 후 fallback 하던 동작.
    @discardableResult
    public static func withLock<T>(
        cli: String,
        timeout: TimeInterval = 600,
        body: () throws -> T
    ) rethrows -> T {
        do {
            return try withLock(slug: cli, timeoutSeconds: timeout, action: body)
        } catch {
            FileHandle.standardError.write(
                Data("⚠ install-lock: \(cli) 락 획득 실패(\(error.localizedDescription)) — 락 없이 진행\n".utf8))
            return try body()
        }
    }

    /// 현재 다른 프로세스나 스레드가 락을 잡고 있는지 확인한다 (논블로킹).
    public static func isLocked(slug: String) -> Bool {
        let path = lockPath(slug: slug)
        guard FileManager.default.fileExists(atPath: path) else { return false }
        var fd = open(path, O_RDWR, 0o644)
        if fd < 0 {
            fd = open(path, O_RDONLY, 0o644)
        }
        guard fd >= 0 else { return false }
        defer { close(fd) }
        let result = flock(fd, LOCK_EX | LOCK_NB)
        if result == 0 {
            flock(fd, LOCK_UN)
            return false
        }
        return true
    }

    public static func isLocked(cli: String) -> Bool {
        isLocked(slug: cli)
    }
}
