import Foundation
import FastDiskIOKit
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
#if canImport(os)
import os
#endif

/// flock 락의 획득/해제 및 자가 교착 방지 상속(Inheritance Bypass)을 전담하는 관리자.
public final class InstanceLockCoordinator: Sendable {
    public struct BypassRule: Sendable {
        public let allowConcurrent: Bool
        public let allowRecursion: Bool
        public let parentPID: pid_t?
        public let currentPPID: pid_t

        public init(
            environment: [String: String] = ProcessInfo.processInfo.environment,
            arguments: [String] = CommandLine.arguments,
            currentPPID: pid_t = getppid()
        ) {
            self.currentPPID = currentPPID
            let hasConcurrentArg = arguments.contains("--allow-concurrent") || arguments.contains("--force")
            let hasConcurrentEnv = Self.isTruthy(environment["SINGLE_INSTANCE_ALLOW_CONCURRENT"]) ||
                                  Self.isTruthy(environment["SINGLE_INSTANCE_FORCE"])
            self.allowConcurrent = hasConcurrentArg || hasConcurrentEnv

            self.allowRecursion = Self.isTruthy(environment["SINGLE_INSTANCE_ALLOW_RECURSION"])

            if let envPPID = environment["SINGLE_INSTANCE_PARENT_PID"].flatMap({ pid_t($0) }), envPPID == currentPPID {
                self.parentPID = envPPID
            } else {
                self.parentPID = nil
            }
        }

        private static func isTruthy(_ value: String?) -> Bool {
            guard let v = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else { return false }
            return v == "1" || v == "true"
        }
    }

    public enum AcquireResult: Sendable {
        case acquired(InstanceLockToken)
        case bypassed(InstanceLockToken)
        case busy(holderPID: pid_t?)
    }

    public init() {}

    /// 비차단(non-blocking) 배타 락을 시도하고 상태를 반환한다.
    public func tryAcquire(
        name: String,
        scope: InstanceLockScope,
        bypassRule: BypassRule = BypassRule()
    ) -> AcquireResult {
        let lockURL = scope.lockFileURL(name: name)
        let fileLock = FastFileLock(url: lockURL)

        guard !fileLock.acquire(exclusive: true, nonBlocking: true) else {
            writePID(getpid(), to: fileLock.fileDescriptor)
            let token = InstanceLockToken(lock: fileLock, lockURL: lockURL)
            return .acquired(token)
        }

        // 락 획득 실패 시: 바이패스 정책 검사
        let holderPID = readHolderPID(from: lockURL)
        let bypassed = bypassToken(at: lockURL, holderPID: holderPID, rule: bypassRule)
        guard let bypassed else { return contestedResult(at: lockURL, holderPID: holderPID) }
        return .bypassed(bypassed)
    }

    private func contestedResult(at lockURL: URL, holderPID: pid_t?) -> AcquireResult {
        recoverStaleLock(at: lockURL, holderPID: holderPID)
            .map(AcquireResult.acquired)
            ?? .busy(holderPID: holderPID)
    }

    private func bypassToken(
        at lockURL: URL,
        holderPID: pid_t?,
        rule: BypassRule
    ) -> InstanceLockToken? {
        let reason: String?
        switch (rule.allowConcurrent, rule.allowRecursion) {
        case (true, _):
            reason = "allow-concurrent"
        case (_, true):
            reason = "recursion-allowed"
        default:
            let parentMatches = rule.parentPID == rule.currentPPID
            let holderMatches = holderPID == rule.currentPPID
            reason = parentMatches
                ? "parent-pid-match"
                : (holderMatches ? "self-deadlock-parent-match" : nil)
        }
        return reason.map { InstanceLockToken(bypassedURL: lockURL, reason: $0) }
    }

    private func recoverStaleLock(at lockURL: URL, holderPID: pid_t?) -> InstanceLockToken? {
        guard let holderPID, !SystemProcessProber().isProcessAlive(pid: holderPID) else { return nil }
        do {
            try FileManager.default.removeItem(at: lockURL)
        } catch CocoaError.fileNoSuchFile {
            return acquireRecoveredLock(at: lockURL)
        } catch {
            return nil
        }
        return acquireRecoveredLock(at: lockURL)
    }

    private func acquireRecoveredLock(at lockURL: URL) -> InstanceLockToken? {
        let recoveredLock = FastFileLock(url: lockURL)
        guard recoveredLock.acquire(exclusive: true, nonBlocking: true) else { return nil }
        writePID(getpid(), to: recoveredLock.fileDescriptor)
        return InstanceLockToken(lock: recoveredLock, lockURL: lockURL)
    }

    private func writePID(_ pid: pid_t, to fd: Int32) {
        guard fd >= 0 else { return }
        ftruncate(fd, 0)
        lseek(fd, 0, SEEK_SET)
        let pidStr = "\(pid)\n"
        _ = pidStr.withCString {
            #if canImport(Darwin)
            Darwin.write(fd, $0, strlen($0))
            #else
            Glibc.write(fd, $0, strlen($0))
            #endif
        }
        #if canImport(Darwin)
        _ = Darwin.fsync(fd)
        #else
        _ = Glibc.fsync(fd)
        #endif
    }

    public func readHolderPID(from url: URL) -> pid_t? {
        let content: String
        do {
            content = try String(contentsOf: url, encoding: .utf8)
        } catch {
            return nil
        }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pid = pid_t(trimmed), pid > 0 else { return nil }
        return pid
    }
}

/// 점유 중인 단일 인스턴스 락을 표현하는 RAII 토큰.
public final class InstanceLockToken: Sendable {
    private let lock: FastFileLock?
    public let lockURL: URL
    public let isBypassed: Bool
    public let bypassReason: String?

    #if canImport(os)
    private let released = OSAllocatedUnfairLock<Bool>(initialState: false)
    private let releaseHook = OSAllocatedUnfairLock<(@Sendable () -> Void)?>(initialState: nil)
    #else
    private let stateLock = NSLock()
    private var _released: Bool = false
    private var _releaseHook: (@Sendable () -> Void)?
    #endif

    public init(lock: FastFileLock, lockURL: URL) {
        self.lock = lock
        self.lockURL = lockURL
        self.isBypassed = false
        self.bypassReason = nil
    }

    public init(bypassedURL: URL, reason: String) {
        self.lock = nil
        self.lockURL = bypassedURL
        self.isBypassed = true
        self.bypassReason = reason
    }

    public func setReleaseHook(_ hook: (@Sendable () -> Void)?) {
        #if canImport(os)
        releaseHook.withLock { $0 = hook }
        #else
        stateLock.lock()
        _releaseHook = hook
        stateLock.unlock()
        #endif
    }

    public var isHeld: Bool {
        #if canImport(os)
        let rel = released.withLock { $0 }
        #else
        stateLock.lock()
        let rel = _released
        stateLock.unlock()
        #endif

        guard !isBypassed else { return !rel }
        return !rel && (lock?.isHeld ?? false)
    }

    public func release() {
        #if canImport(os)
        let shouldRelease = released.withLock { rel -> Bool in
            guard !rel else { return false }
            rel = true
            return true
        }
        let hook = releaseHook.withLock { $0 }
        #else
        stateLock.lock()
        let shouldRelease: Bool
        if !_released {
            _released = true
            shouldRelease = true
        } else {
            shouldRelease = false
        }
        let hook = _releaseHook
        stateLock.unlock()
        #endif

        guard shouldRelease else { return }
        releaseFileLock()
        hook?()
    }

    private func releaseFileLock() {
        guard let lock else { return }
        let fd = lock.fileDescriptor
        guard fd >= 0 else {
            lock.release()
            return
        }
        ftruncate(fd, 0)
        lock.release()
    }

    deinit {
        release()
    }
}

// MARK: - Equatable & InstanceLocking Conformances

extension InstanceLockToken: Equatable {
    public static func == (lhs: InstanceLockToken, rhs: InstanceLockToken) -> Bool {
        lhs === rhs
    }
}

extension InstanceLockCoordinator: InstanceLocking {
    public func tryAcquire(url: URL) -> InstanceLockToken? {
        let fileLock = FastFileLock(url: url)
        guard fileLock.acquire(exclusive: true, nonBlocking: true) else {
            return nil
        }
        writePID(getpid(), to: fileLock.fileDescriptor)
        return InstanceLockToken(lock: fileLock, lockURL: url)
    }

    public func writeHolderPID(_ pid: pid_t, to url: URL) {
        let pidStr = "\(pid)\n"
        do {
            try pidStr.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            FileHandle.standardError.write(Data("SingleInstanceKit: \(error)\n".utf8))
        }
    }

    public func removeLockFile(at url: URL) -> Bool {
        (try? FileManager.default.removeItem(at: url)) != nil
    }
}
