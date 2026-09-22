import Foundation
import os
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

// MARK: - TwoTierFileLockError

/// 2계층 파일 락 동기화 오류.
public enum TwoTierFileLockError: LocalizedError, Equatable, Sendable {
    case timeout(url: URL, tier: Tier, elapsed: TimeInterval)
    case fileOpenFailed(path: String, errno: Int32)
    case lockFailed(path: String, errno: Int32)

    public enum Tier: String, Sendable {
        case inProcess = "in-process (Tier 1 NSRecursiveLock)"
        case interProcess = "inter-process (Tier 2 OS flock)"
    }

    public var errorDescription: String? {
        switch self {
        case .timeout(let url, let tier, let elapsed):
            return "2계층 파일 락 취득 타임아웃 (\(tier.rawValue), \(String(format: "%.3f", elapsed))s 경과): \(url.path)"
        case .fileOpenFailed(let path, let errno):
            return "락 파일 열기 실패 (\(path)): errno \(errno)"
        case .lockFailed(let path, let errno):
            return "OS flock 실패 (\(path)): errno \(errno)"
        }
    }
}

// MARK: - InProcessLockRegistry (Tier 1)

/// 각 정본 락 경로별 인메모리 NSRecursiveLock 및 재진입 상태.
private final class InProcessLockEntry: Sendable {
    let recursiveLock = NSRecursiveLock()
    private let state = OSAllocatedUnfairLock(initialState: (reentrancyDepth: 0, descriptor: Int32(-1)))

    var reentrancyDepth: Int {
        get { state.withLock { $0.reentrancyDepth } }
        set { state.withLock { $0.reentrancyDepth = newValue } }
    }

    var descriptor: Int32 {
        get { state.withLock { $0.descriptor } }
        set { state.withLock { $0.descriptor = newValue } }
    }
}

/// 프로세스 내부 멀티스레드 상호 배제를 위한 인메모리 락 레지스트리.
private final class InProcessLockRegistry: Sendable {
    static let shared = InProcessLockRegistry()

    private let storage = OSAllocatedUnfairLock<[String: InProcessLockEntry]>(initialState: [:])

    private init() {}

    func entry(for path: String) -> InProcessLockEntry {
        storage.withLock { map in
            if let existing = map[path] {
                return existing
            }
            let newEntry = InProcessLockEntry()
            map[path] = newEntry
            return newEntry
        }
    }
}

// MARK: - TwoTierFileLock

/// 프로세스 내부 멀티스레드 경합(Tier 1: 인메모리 `NSRecursiveLock`)과
/// 프로세스 간 상호 배제(Tier 2: OS `flock` with 지수 백오프/지터)를 결합한 2계층 동기화 엔진.
///
/// - Tier 1: 동일 프로세스 내 스레드 간 불필요한 OS 파일 디스크립터 경합을 인메모리 `NSRecursiveLock`으로 사전에 배제하며,
///   동일 스레드 내 재진입(re-entrancy)을 허용합니다.
/// - Tier 2: 서로 다른 프로세스 간의 물리적 파일 쓰기 충돌을 OS `flock(LOCK_EX / LOCK_SH)`과 지수 백오프/지터를 통해
///   완전한 상호 배제 및 공정성(Fairness)을 보장합니다.
public enum TwoTierFileLock: Sendable {

    /// 기본 파일 락 취득 타임아웃 (초 단위).
    public static let defaultLockTimeout: TimeInterval = 10.0

    /// 지정된 URL 경로에서 2계층(인메모리 + OS flock) 락을 취득한 상태로 클로저를 실행합니다.
    ///
    /// - Parameters:
    ///   - url: 락 파일 대상 URL
    ///   - exclusive: 배타적 잠금 여부 (기본 true: 배타적 쓰기 잠금, false: 공유 읽기 잠금)
    ///   - timeout: 전체 락 취득 대기 타임아웃(초 단위, 기본 defaultLockTimeout)
    ///   - body: 락을 취득한 상태에서 실행할 클로저
    /// - Returns: 클로저의 반환값
    @discardableResult
    public static func withLock<T>(
        at url: URL,
        exclusive: Bool = true,
        timeout: TimeInterval = defaultLockTimeout,
        _ body: () throws -> T
    ) throws -> T {
        let startTime = Date()
        let canonicalPath = url.standardizedFileURL.resolvingSymlinksInPath().path

        // MARK: Tier 1 - In-Process NSRecursiveLock
        let entry = InProcessLockRegistry.shared.entry(for: canonicalPath)
        let tier1Deadline = startTime.addingTimeInterval(timeout)

        guard entry.recursiveLock.lock(before: tier1Deadline) else {
            let elapsed = Date().timeIntervalSince(startTime)
            throw TwoTierFileLockError.timeout(url: url, tier: .inProcess, elapsed: elapsed)
        }
        defer { entry.recursiveLock.unlock() }

        // 동일 스레드 내 재진입(re-entrant)인 경우: OS flock은 이미 취득되어 있으므로 중복 취득 생략
        if entry.reentrancyDepth > 0 {
            entry.reentrancyDepth += 1
            defer { entry.reentrancyDepth -= 1 }
            return try body()
        }

        // 최초 진입: Tier 2 OS flock with Exponential Backoff & Jitter
        let elapsedAfterTier1 = Date().timeIntervalSince(startTime)
        let remainingTimeout = max(0, timeout - elapsedAfterTier1)
        if remainingTimeout <= 0 {
            throw TwoTierFileLockError.timeout(url: url, tier: .inProcess, elapsed: elapsedAfterTier1)
        }

        try AppPaths.ensureDirectory(at: url.deletingLastPathComponent(), permissions: 0o700)

        #if canImport(Darwin)
        let descriptor = Darwin.open(url.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        #elseif canImport(Glibc)
        let descriptor = Glibc.open(url.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        #endif

        guard descriptor >= 0 else {
            throw TwoTierFileLockError.fileOpenFailed(path: url.path, errno: errno)
        }

        do {
            try acquireOSLock(
                descriptor: descriptor,
                url: url,
                exclusive: exclusive,
                timeout: remainingTimeout,
                startTime: startTime
            )
        } catch {
            #if canImport(Darwin)
            Darwin.close(descriptor)
            #elseif canImport(Glibc)
            Glibc.close(descriptor)
            #endif
            throw error
        }

        entry.descriptor = descriptor
        entry.reentrancyDepth = 1

        defer {
            entry.reentrancyDepth = 0
            flock(descriptor, LOCK_UN)
            #if canImport(Darwin)
            Darwin.close(descriptor)
            #elseif canImport(Glibc)
            Glibc.close(descriptor)
            #endif
            entry.descriptor = -1
        }

        return try body()
    }

    /// 슬러그와 락 파일 이름을 받아 AppPaths 정본 락 경로에서 2계층 락을 취득하고 클로저를 실행합니다.
    @discardableResult
    public static func withLock<T>(
        slug: String,
        name: String = "app.lock",
        exclusive: Bool = true,
        timeout: TimeInterval = defaultLockTimeout,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL? = nil,
        _ body: () throws -> T
    ) throws -> T {
        let lockPath = AppPaths.lockFile(
            slug: slug,
            name: name,
            environment: environment,
            homeDirectory: homeDirectory
        )
        return try withLock(at: lockPath.url, exclusive: exclusive, timeout: timeout, body)
    }

    /// LockPath 정본 인스턴스에서 2계층 락을 취득하고 클로저를 실행합니다.
    @discardableResult
    public static func withLock<T>(
        _ lockPath: LockPath,
        exclusive: Bool = true,
        timeout: TimeInterval = defaultLockTimeout,
        _ body: () throws -> T
    ) throws -> T {
        try withLock(at: lockPath.url, exclusive: exclusive, timeout: timeout, body)
    }

    // MARK: - Private Helpers

    #if canImport(Darwin) || canImport(Glibc)
    private static func acquireOSLock(
        descriptor: Int32,
        url: URL,
        exclusive: Bool,
        timeout: TimeInterval,
        startTime: Date
    ) throws {
        let op = (exclusive ? LOCK_EX : LOCK_SH) | LOCK_NB
        let deadline = Date().addingTimeInterval(timeout)

        var currentBackoffMs: Double = 1.0  // 초기 1ms 백오프
        let maxBackoffMs: Double = 50.0    // 최대 50ms 백오프

        while true {
            if flock(descriptor, op) == 0 {
                return
            }
            let err = errno
            guard err == EWOULDBLOCK || err == EAGAIN else {
                throw TwoTierFileLockError.lockFailed(path: url.path, errno: err)
            }

            let now = Date()
            if now >= deadline {
                let totalElapsed = now.timeIntervalSince(startTime)
                throw TwoTierFileLockError.timeout(url: url, tier: .interProcess, elapsed: totalElapsed)
            }

            // 지터(Jitter): 백오프 값의 0.5배 ~ 1.5배 사이 무작위 지연을 적용하여 썬더링 허드 방지
            let jitterFactor = Double.random(in: 0.5...1.5)
            let sleepMs = min(currentBackoffMs * jitterFactor, maxBackoffMs)
            let sleepNsec = Int(sleepMs * 1_000_000)
            var req = timespec(tv_sec: sleepNsec / 1_000_000_000, tv_nsec: sleepNsec % 1_000_000_000)
            nanosleep(&req, nil)

            currentBackoffMs = min(currentBackoffMs * 2.0, maxBackoffMs)
        }
    }
    #endif
}
