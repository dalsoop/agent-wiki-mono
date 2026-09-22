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

/// CLI 도구 전용 중복 실행 방지 가드 SSOT.
///
/// 내부적으로 `InstanceLockScope`, `InstanceLockCoordinator`, `InstanceLockToken` 객체 모델에 위임하여
/// SRP(단일 책임 원칙)와 테넌트/워크트리 격리를 보장한다.
public enum SingleInstanceCLI {

    /// 락의 적용 범위(스코프). `InstanceLockScope`의 별칭.
    public typealias Scope = InstanceLockScope

    /// 점유 중인 단일 인스턴스 락을 표현하는 RAII 토큰. `InstanceLockToken`의 별칭.
    public typealias Token = InstanceLockToken

    // MARK: - Active Tokens Registry (Global Retention & Isolation)

    #if canImport(os)
    private static let activeTokens = OSAllocatedUnfairLock<[String: Token]>(initialState: [:])
    #else
    private static let registryLock = NSLock()
    private static var _activeTokens: [String: Token] = [:]
    #endif

    private static func registerToken(_ token: Token, for path: String) {
        #if canImport(os)
        activeTokens.withLock { $0[path] = token }
        #else
        registryLock.lock()
        _activeTokens[path] = token
        registryLock.unlock()
        #endif

        token.setReleaseHook {
            unregisterToken(for: path)
        }
    }

    fileprivate static func unregisterToken(for path: String) {
        #if canImport(os)
        activeTokens.withLock { _ = $0.removeValue(forKey: path) }
        #else
        registryLock.lock()
        _ = _activeTokens.removeValue(forKey: path)
        registryLock.unlock()
        #endif
    }

    /// 현재 프로세스가 점유 중인 모든 토큰을 해제한다 (주로 테스트 격리용).
    public static func releaseAll() {
        #if canImport(os)
        let tokens = activeTokens.withLock { dict -> [Token] in
            let copy = Array(dict.values)
            dict.removeAll()
            return copy
        }
        #else
        registryLock.lock()
        let tokens = Array(_activeTokens.values)
        _activeTokens.removeAll()
        registryLock.unlock()
        #endif

        for token in tokens {
            token.release()
        }
    }

    // MARK: - Process ID & Lock File Inspection

    /// 락 파일에서 점유 중인 프로세스의 PID를 읽는다 (advisory lock 상태에서도 안전하게 읽음).
    public static func readHolderPID(from url: URL) -> pid_t? {
        InstanceLockCoordinator().readHolderPID(from: url)
    }

    // MARK: - Self-Deadlock Prevention & Bypass Inspection

    public static func shouldBypass(
        lockURL: URL,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = CommandLine.arguments,
        currentPPID: pid_t = getppid()
    ) -> (bypass: Bool, reason: String?) {
        if arguments.contains("--allow-concurrent") {
            return (true, "command-line argument '--allow-concurrent'")
        }
        if arguments.contains("--force") {
            return (true, "command-line argument '--force'")
        }
        if environment["SINGLE_INSTANCE_ALLOW_CONCURRENT"] == "1" ||
           environment["SINGLE_INSTANCE_ALLOW_CONCURRENT"]?.lowercased() == "true" {
            return (true, "environment variable SINGLE_INSTANCE_ALLOW_CONCURRENT=1")
        }
        if environment["SINGLE_INSTANCE_FORCE"] == "1" ||
           environment["SINGLE_INSTANCE_FORCE"]?.lowercased() == "true" {
            return (true, "environment variable SINGLE_INSTANCE_FORCE=1")
        }

        let allowRecursion = environment["SINGLE_INSTANCE_ALLOW_RECURSION"] == "1" ||
                             environment["SINGLE_INSTANCE_ALLOW_RECURSION"]?.lowercased() == "true"
        let parentPIDEnv = environment["SINGLE_INSTANCE_PARENT_PID"].flatMap { pid_t($0) }
        let matchesParentPID = parentPIDEnv != nil && parentPIDEnv == currentPPID
        let holderPID = readHolderPID(from: lockURL)

        if allowRecursion {
            if let holder = holderPID {
                return (true, "SINGLE_INSTANCE_ALLOW_RECURSION=1 (lock held by PID \(holder))")
            } else {
                return (true, "SINGLE_INSTANCE_ALLOW_RECURSION=1")
            }
        }

        if matchesParentPID {
            return (true, "SINGLE_INSTANCE_PARENT_PID matches current parent PID (\(currentPPID))")
        }

        if let holder = holderPID, holder == currentPPID {
            return (true, "self-deadlock bypass: lock holder matches parent PID (\(currentPPID))")
        }

        return (false, nil)
    }

    public static func makeRecursionEnvironment(
        base: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        var env = base
        env["SINGLE_INSTANCE_ALLOW_RECURSION"] = "1"
        env["SINGLE_INSTANCE_PARENT_PID"] = "\(getpid())"
        return env
    }

    // MARK: - Lock Acquisition

    public static func acquire(
        name: String,
        scope: Scope = .host,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = CommandLine.arguments,
        currentPPID: pid_t = getppid()
    ) -> Token? {
        let coordinator = InstanceLockCoordinator()
        let bypassRule = InstanceLockCoordinator.BypassRule(
            environment: environment,
            arguments: arguments,
            currentPPID: currentPPID
        )
        let result = coordinator.tryAcquire(name: name, scope: scope, bypassRule: bypassRule)
        switch result {
        case .acquired(let token), .bypassed(let token):
            registerToken(token, for: token.lockURL.path)
            return token
        case .busy:
            return nil
        }
    }

    public static func tryAcquire(
        name: String,
        scope: Scope = .host,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = CommandLine.arguments,
        currentPPID: pid_t = getppid()
    ) -> Token? {
        acquire(
            name: name,
            scope: scope,
            environment: environment,
            arguments: arguments,
            currentPPID: currentPPID
        )
    }

    // MARK: - Exit Guard

    @discardableResult
    public static func exitIfAlreadyRunning(
        name: String,
        scope: Scope = .host,
        message: String? = nil,
        exitCode: Int32 = 0,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = CommandLine.arguments
    ) -> Token {
        exitIfAlreadyRunning(
            name: name,
            scope: scope,
            message: message,
            exitCode: exitCode,
            environment: environment,
            arguments: arguments,
            currentPPID: getppid(),
            stderrWriter: { msg in
                FileHandle.standardError.write(Data((msg + "\n").utf8))
            },
            exitHandler: { code in
                exit(code)
            }
        )!
    }

    @discardableResult
    static func exitIfAlreadyRunning(
        name: String,
        scope: Scope = .host,
        message: String? = nil,
        exitCode: Int32 = 0,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = CommandLine.arguments,
        currentPPID: pid_t = getppid(),
        stderrWriter: (String) -> Void,
        exitHandler: (Int32) -> Void
    ) -> Token? {
        if let token = acquire(
            name: name,
            scope: scope,
            environment: environment,
            arguments: arguments,
            currentPPID: currentPPID
        ) {
            return token
        }
        let defaultMsg = "[\(name)] Another instance is already running (\(scopeDescription(scope))). Exiting."
        let finalMsg = message ?? defaultMsg
        stderrWriter(finalMsg)
        exitHandler(exitCode)
        return nil
    }

    // MARK: - Path Resolution Helpers

    public static func resolveLockURL(name: String, scope: Scope) -> URL {
        scope.lockFileURL(name: name)
    }

    public static func findWorktreeRoot(
        from startURL: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    ) -> URL {
        InstanceLockScope.findWorktreeRoot(from: startURL)
    }

    private static func scopeDescription(_ scope: Scope) -> String {
        switch scope {
        case .host(let dir):
            return "scope: host, path: \(dir?.path ?? "/tmp")"
        case .worktree(let root):
            return "scope: worktree, root: \(root?.path ?? findWorktreeRoot().path)"
        case .tenant(let slug, let root):
            return "scope: tenant(\(slug)), root: \(root?.path ?? findWorktreeRoot().path)"
        }
    }

    // MARK: - Standard Informational Guard

    /// 표준 정보 조회 플래그(`help`, `version`, `status`, `capabilities` 등)를 자동 바이패스하는 단일화된 CLI 가드 SSOT.
    ///
    /// 모든 CLI `main.swift` 상단에서 반복 복제되던 10~15줄의 `isInformational` 검사를 1줄로 단일화한다.
    @discardableResult
    public static func guardStandard(
        name: String,
        scope: Scope = .worktree,
        arguments: [String] = CommandLine.arguments,
        extraInformational: Set<String> = [],
        message: String? = nil,
        exitCode: Int32 = 0
    ) -> Token? {
        let args = Array(arguments.dropFirst())
        let cmd = args.first ?? "help"
        let baseInformational: Set<String> = [
            "help", "-h", "--help",
            "version", "-V", "-v", "--version",
            "capabilities",
            "status",
            "doctor",
            "open"
        ]
        let isInfo = baseInformational.union(extraInformational).contains(cmd)
            || args.contains("--help")
            || args.contains("-h")

        if args.contains("--force") || isInfo {
            return nil
        }

        return exitIfAlreadyRunning(
            name: name,
            scope: scope,
            message: message ?? "[\(name)] Another instance is already running for this \(scopeDescription(scope)). Skipping duplicate run.",
            exitCode: exitCode,
            arguments: arguments
        )
    }

    /// 실행 중인 프로세스 바이너리명(`CommandLine.arguments[0]`)에서 CLI 이름을 런타임 자동 추출하고,
    /// 모노레포 공통 규약에 따른 정보성 명령 바이패스를 수행하는 하드코딩 0개 표준 엔트리 가드.
    @discardableResult
    public static func autoGuard(
        scope: Scope = .worktree,
        arguments: [String] = CommandLine.arguments,
        extraInformational: Set<String> = [],
        message: String? = nil,
        exitCode: Int32 = 0
    ) -> Token? {
        let binaryName = URL(fileURLWithPath: arguments.first ?? "unknown-cli").lastPathComponent
        return guardStandard(
            name: binaryName,
            scope: scope,
            arguments: arguments,
            extraInformational: extraInformational,
            message: message,
            exitCode: exitCode
        )
    }
}
