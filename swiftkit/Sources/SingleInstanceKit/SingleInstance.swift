import Foundation
import FastDiskIOKit

#if canImport(AppKit)
import AppKit
#endif

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

// MARK: - Legacy Running Instance Query Protocol

/// 같은 bundle ID 로 실행 중인 다른 인스턴스 조회를 추상화 — 테스트에서 목으로 대체 가능
/// (CommandKit 의 `CommandRunning` 패턴과 동일).
public protocol RunningInstanceQuerying: Sendable {
    /// 자신을 제외한, 같은 bundle ID 의 실행 중 인스턴스 수.
    func otherInstanceCount(bundleIdentifier: String) -> Int
}

/// NSWorkspace 기반 표준 구현.
public struct WorkspaceInstanceQuery: RunningInstanceQuerying {
    public init() {}
    public func otherInstanceCount(bundleIdentifier: String) -> Int {
        #if canImport(AppKit)
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            .count
        #else
        0
        #endif
    }
}

// MARK: - Guard Decision

/// 단일 인스턴스 가드의 판정 결과.
/// C `exit(0)` 직접 호출 대신 이 결과를 반환하여 호출 측(앱/CLI)이 자체 수명 주기를 제어할 수 있다.
public enum GuardDecision: Sendable, Equatable {
    /// 락을 정상 획득(또는 상속 바이패스 허용)하여 현재 인스턴스가 주도적으로 실행을 지속함.
    case run(token: InstanceLockToken?)
    /// 다른 활성 프로세스가 이미 락을 점유 중이므로 현재 인스턴스가 실행을 양보해야 함.
    case yieldToExisting(holderPID: pid_t?)
    /// 이전 점유 프로세스가 비정상 종료(ESRCH/사망)하여 Stale Lock을 감지 및 자가 치유(Self-Healing) 후 신규 락을 획득함.
    case staleRecovered(previousPID: pid_t?, token: InstanceLockToken?)

    /// 프로세스가 계속 실행되어야 하는지 여부 (`run` 또는 `staleRecovered`일 때 true).
    public var shouldRun: Bool {
        switch self {
        case .run, .staleRecovered:
            return true
        case .yieldToExisting:
            return false
        }
    }

    /// 획득된 락 토큰 (실행 가능한 상태일 때 반환, 번들 기반 또는 토큰 없는 경우 nil일 수 있음).
    public var token: InstanceLockToken? {
        switch self {
        case .run(let token), .staleRecovered(_, let token):
            return token
        case .yieldToExisting:
            return nil
        }
    }

    /// 점유 중이거나 직전에 점유했던 프로세스의 PID.
    public var holderPID: pid_t? {
        switch self {
        case .run:
            return nil
        case .yieldToExisting(let pid):
            return pid
        case .staleRecovered(let pid, _):
            return pid
        }
    }
}

// MARK: - Process Probing Protocol & Implementation

/// 프로세스의 OS 레벨 생존 여부를 조회하는 프로토콜 (단위 테스트 DI 지원).
public protocol ProcessProbing: Sendable {
    /// 주어진 PID의 프로세스가 현재 OS 상에서 살아있는지 검사한다.
    func isProcessAlive(pid: pid_t) -> Bool
}

/// `kill(pid, 0)` 기반 POSIX 표준 프로세스 생존 검사 구현체.
public struct SystemProcessProber: ProcessProbing {
    public init() {}

    public func isProcessAlive(pid: pid_t) -> Bool {
        guard pid > 0 else { return false }
        guard kill(pid, 0) != 0 else { return true }

        #if canImport(Darwin)
        let err = Darwin.errno
        #elseif canImport(Glibc)
        let err = Glibc.errno
        #else
        let err = errno
        #endif

        // ESRCH: No such process (프로세스 부재 / 완전히 사망함)
        switch err {
        case ESRCH:
            return false
        case EPERM:
            return true
        default:
            return false
        }
    }
}

// MARK: - Instance Locking Protocol & Implementation

/// 단일 인스턴스 락 파일의 점유, 해제, PID 조회를 추상화하는 프로토콜.
public protocol InstanceLocking: Sendable {
    /// 지정된 파일 URL에 대한 비차단 배타 락 획득 시도
    func tryAcquire(url: URL) -> InstanceLockToken?
    /// 락 파일에 기록된 점유자 PID 읽기
    func readHolderPID(from url: URL) -> pid_t?
    /// 락 파일에 PID 기록
    func writeHolderPID(_ pid: pid_t, to url: URL)
    /// 락 파일 삭제 (Stale Lock 자가 치유 시 언링크)
    func removeLockFile(at url: URL) -> Bool
}

extension InstanceLocking {
    public func tryAcquire(name: String, scope: InstanceLockScope) -> InstanceLockToken? {
        tryAcquire(url: scope.lockFileURL(name: name))
    }

    public func readHolderPID(name: String, scope: InstanceLockScope) -> pid_t? {
        readHolderPID(from: scope.lockFileURL(name: name))
    }

    public func removeLockFile(name: String, scope: InstanceLockScope) -> Bool {
        removeLockFile(at: scope.lockFileURL(name: name))
    }
}

/// FastFileLock 기반 파일시스템 락킹 표준 구현체.
public struct FileInstanceLocking: InstanceLocking {
    public init() {}

    public func tryAcquire(url: URL) -> InstanceLockToken? {
        let fileLock = FastFileLock(url: url)
        guard fileLock.acquire(exclusive: true, nonBlocking: true) else {
            return nil
        }
        writePID(getpid(), to: fileLock.fileDescriptor)
        return InstanceLockToken(lock: fileLock, lockURL: url)
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

    public func writeHolderPID(_ pid: pid_t, to url: URL) {
        let pidStr = "\(pid)\n"
        do {
            try pidStr.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            FileHandle.standardError.write(Data("SingleInstanceKit: \(error)\n".utf8))
        }
    }

    private func writePID(_ pid: pid_t, to fd: Int32) {
        guard fd >= 0 else { return }
        ftruncate(fd, 0)
        lseek(fd, 0, SEEK_SET)
        let pidStr = "\(pid)\n"
        pidStr.withCString {
            #if canImport(Darwin)
            Darwin.write(fd, $0, strlen($0))
            Darwin.fsync(fd)
            #elseif canImport(Glibc)
            Glibc.write(fd, $0, strlen($0))
            Glibc.fsync(fd)
            #endif
        }
    }

    public func removeLockFile(at url: URL) -> Bool {
        do {
            try FileManager.default.removeItem(at: url)
            return true
        } catch {
            return false
        }
    }
}

// MARK: - Instance Guarding Protocol & Implementation

/// 단일 인스턴스 실행 여부를 평가하고 판정(GuardDecision)을 내리는 프로토콜.
public protocol InstanceGuarding: Sendable {
    func evaluate(name: String, scope: InstanceLockScope) -> GuardDecision
}

/// DI 기반 SingleInstanceGuard 표준 구현체.
/// Stale Lock 0ms 자가 치유 및 무충돌 다중 인스턴스 격리를 담당한다.
public struct SingleInstanceGuard: InstanceGuarding {
    public let locking: InstanceLocking
    public let prober: ProcessProbing

    public init(
        locking: InstanceLocking = FileInstanceLocking(),
        prober: ProcessProbing = SystemProcessProber()
    ) {
        self.locking = locking
        self.prober = prober
    }

    public func evaluate(name: String, scope: InstanceLockScope) -> GuardDecision {
        let lockURL = scope.lockFileURL(name: name)
        if let recovered = recoverStaleHolder(at: lockURL) { return recovered }

        // 2. 락 획득 시도 (파일 부재, 정상 경쟁, 또는 유효 홀더 검사 통과 후)
        if let token = locking.tryAcquire(url: lockURL) {
            return .run(token: token)
        }

        // 3. 락 획득 실패 시 점유자 생존 재확인
        guard let holderPID = locking.readHolderPID(from: lockURL) else {
            return .yieldToExisting(holderPID: nil)
        }
        guard !prober.isProcessAlive(pid: holderPID) else {
            return .yieldToExisting(holderPID: holderPID)
        }
        return recoverContendedStaleHolder(holderPID, at: lockURL)
    }

    private func recoverStaleHolder(at lockURL: URL) -> GuardDecision? {
        guard let holderPID = locking.readHolderPID(from: lockURL) else { return nil }
        guard !prober.isProcessAlive(pid: holderPID) else { return nil }
        _ = locking.removeLockFile(at: lockURL)
        guard let token = locking.tryAcquire(url: lockURL) else { return nil }
        return .staleRecovered(previousPID: holderPID, token: token)
    }

    private func recoverContendedStaleHolder(_ holderPID: pid_t, at lockURL: URL) -> GuardDecision {
        _ = locking.removeLockFile(at: lockURL)
        guard let token = locking.tryAcquire(url: lockURL) else {
            return .yieldToExisting(holderPID: locking.readHolderPID(from: lockURL))
        }
        return .staleRecovered(previousPID: holderPID, token: token)
    }
}

// MARK: - SingleInstance Unified Facade

/// 앱 중복 실행 방지 및 단일 인스턴스 수명 주기 통합 관리 파사드.
public enum SingleInstance {
    /// 기본 인스턴스 가드
    public static let defaultGuard: any InstanceGuarding = SingleInstanceGuard()

    // MARK: - Path & UDS Helpers

    /// MurmurHash64A 기반 30바이트 고정 길이 소켓 경로 (`/tmp/sik_<hex16>.sock`) 생성.
    /// Darwin UDS 104바이트 한계를 원천적으로 초과하지 않는다.
    public static func socketPath(for key: String) -> String {
        let hash = MurmurHash64A.hash(string: key, seed: 0x514B_4954) // "SIKIT"
        return String(format: "/tmp/sik_%016llx.sock", hash)
    }

    /// MurmurHash64A 기반 30바이트 고정 길이 소켓 URL 생성.
    public static func socketURL(for key: String) -> URL {
        URL(fileURLWithPath: socketPath(for: key))
    }

    /// 테넌트 격리 락 파일 경로 (`~/.tenants/<slug>/.locks/<name>.lock`) 계산.
    public static func tenantLockURL(slug: String, name: String, root: URL? = nil) -> URL {
        InstanceLockScope.tenant(slug: slug, root: root).lockFileURL(name: name)
    }

    // MARK: - Non-Terminating Evaluation (OOP Lifecycle)

    /// 객체 지향 DI 가드를 통한 단일 인스턴스 실행 판정.
    /// C `exit(0)`을 직접 호출하지 않고 `GuardDecision`을 반환하여 앱이 수명 주기를 주도한다.
    @discardableResult
    public static func evaluate(
        name: String,
        scope: InstanceLockScope = .host,
        guarder: InstanceGuarding = defaultGuard
    ) -> GuardDecision {
        guarder.evaluate(name: name, scope: scope)
    }

    /// 번들 식별자 기반 실행 여부 평가 (AppKit 환경 등).
    public static func evaluate(
        query: RunningInstanceQuerying = WorkspaceInstanceQuery(),
        bundleIdentifier: String? = Foundation.Bundle.main.bundleIdentifier
    ) -> GuardDecision {
        if shouldExit(query: query, bundleIdentifier: bundleIdentifier) {
            return .yieldToExisting(holderPID: nil)
        }
        return .run(token: nil)
    }

    // MARK: - Standard & Legacy Guard Methods

    /// 이름과 스코프를 지정하여 호출하는 진입점.
    /// 이미 실행 중인 경우 stderr 출력 후 `exitHandler`(기본값 `exit(0)`)를 호출한다.
    @discardableResult
    public static func exitIfAlreadyRunning(
        name: String,
        scope: InstanceLockScope = .host,
        guarder: InstanceGuarding = defaultGuard,
        stderrWriter: (String) -> Void = { msg in FileHandle.standardError.write(Data((msg + "\n").utf8)) },
        exitHandler: ((Int32) -> Void)? = nil
    ) -> GuardDecision {
        let decision = evaluate(name: name, scope: scope, guarder: guarder)
        if case .yieldToExisting(let holderPID) = decision {
            let desc = holderPID.map { " (held by PID \($0))" } ?? ""
            stderrWriter("[\(name)] Another instance is already running\(desc). Exiting.")
            if let exitHandler {
                exitHandler(0)
            } else {
                exit(0)
            }
        }
        return decision
    }

    /// 제품 고정 키로 사용자 세션 안의 GUI 프로세스를 하나만 유지한다.
    public static func exitIfAlreadyRunning(
        lockName: String,
        lockDirectory: URL = FileManager.default.temporaryDirectory
    ) {
        _ = acquireOrExit(
            lockName: lockName,
            lockDirectory: lockDirectory,
            stderrWriter: { message in
                FileHandle.standardError.write(Data((message + "\n").utf8))
            },
            exitHandler: { code in exit(code) }
        )
    }

    /// 제품 고정 키 가드의 테스트 가능한 내부 진입점.
    @discardableResult
    static func acquireOrExit(
        lockName: String,
        lockDirectory: URL,
        stderrWriter: (String) -> Void,
        exitHandler: (Int32) -> Void
    ) -> SingleInstanceCLI.Token? {
        SingleInstanceCLI.exitIfAlreadyRunning(
            name: lockName,
            scope: .host(directory: lockDirectory),
            message: "[\(lockName)] Another product instance is already running. Exiting.",
            environment: [:],
            arguments: [],
            stderrWriter: stderrWriter,
            exitHandler: exitHandler
        )
    }

    /// 같은 bundle ID 의 다른 인스턴스가 이미 있으면 현재 프로세스를 종료한다.
    /// bundle ID 가 없으면(테스트 러너·`swift run` 맨바이너리) 아무것도 하지 않는다.
    public static func exitIfAlreadyRunning(
        query: RunningInstanceQuerying = WorkspaceInstanceQuery(),
        bundleIdentifier: String? = Foundation.Bundle.main.bundleIdentifier,
        exitHandler: ((Int32) -> Void)? = nil
    ) {
        #if canImport(AppKit)
        let decision = evaluate(query: query, bundleIdentifier: bundleIdentifier)
        if case .yieldToExisting = decision {
            if let exitHandler {
                exitHandler(0)
            } else {
                exit(0)
            }
        }
        #endif
    }

    /// 종료 판정만 분리 — 테스트 대상.
    static func shouldExit(query: RunningInstanceQuerying, bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else { return false }
        return query.otherInstanceCount(bundleIdentifier: bundleIdentifier) > 0
    }
}
