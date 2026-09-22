import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// CommandKit 표준 안전 프로세스 러너 SSOT.
///
/// Core 레이어에서 `Process()` 직접 생성을 금지하고 프로세스 생명주기 및 파이프 데드락을 방어하는 단일 진실의 원천입니다.
/// - 64KB 파이프 버퍼 초과로 인한 데드락 방지 (비동기 파이프 드레인)
/// - 타임아웃 강제 적용 (기본 30초, 만료 시 SIGTERM -> SIGKILL 강제 종료 승격)
/// - 작업 디렉터리, 환경변수 정제 (SWIFT_EXEC 오염 방지 및 표준 PATH 보강)
/// - 동기(`runSync`, `run`), 비동기(`runAsync`, `run` async throws), 스트리밍(`lines`), 스폰(`spawn`) API 완비
/// - 인스턴스(`CommandRunning` 준수) 및 정적(static) 메서드 동시 지원
public struct SafeProcessRunner: CommandRunning, Sendable {
    /// 기본 타임아웃 (30.0초).
    public static let defaultTimeout: TimeInterval = 30.0

    public init() {}

    // MARK: - Synchronous Execution (Positional)

    /// 외부 프로세스를 동기적으로 안전하게 실행합니다 (위치 인자 스타일).
    ///
    /// - Parameters:
    ///   - launchPath: 실행 파일 절대 경로.
    ///   - arguments: 명령행 인자 목록.
    ///   - environment: 환경 변수 맵 (선택사항).
    ///   - workingDirectory: 작업 디렉터리 URL (선택사항).
    ///   - input: 표준 입력(stdin) 데이터 (선택사항).
    ///   - timeout: 타임아웃 초 (기본 30초). nil 전달 시 무제한 대기.
    /// - Returns: 실행 결과 (`ProcessResult`).
    @discardableResult
    public static func run(
        _ launchPath: String,
        _ arguments: [String] = [],
        environment: [String: String]? = nil,
        workingDirectory: URL? = nil,
        input: Data? = nil,
        timeout: TimeInterval? = defaultTimeout,
        onLine: (@Sendable (String) -> Void)? = nil,
        isCancelled: (@Sendable () -> Bool)? = nil
    ) -> ProcessResult {
        #if os(iOS)
        return ProcessResult(stdout: "", stderr: "local command execution is unavailable on iOS", exitCode: 127)
        #else
        return CommandKitSync.run(
            launchPath,
            arguments,
            environment: environment,
            workingDirectory: workingDirectory,
            input: input,
            timeout: timeout,
            onLine: onLine,
            isCancelled: isCancelled
        )
        #endif
    }

    /// `CommandSpecification` 명세에 따라 프로세스를 동기적으로 실행합니다.
    @discardableResult
    public static func run(_ spec: CommandSpecification) -> ProcessResult {
        #if os(iOS)
        return ProcessResult(stdout: "", stderr: "local command execution is unavailable on iOS", exitCode: 127)
        #else
        return CommandKitSync.run(spec)
        #endif
    }

    // MARK: - Synchronous Execution (Labeled)

    /// 외부 프로세스를 레이블 매개변수 형태로 직관적으로 실행합니다.
    ///
    /// ```swift
    /// let result = SafeProcessRunner.run(executable: "/usr/bin/git", arguments: ["status"])
    /// if result.ok {
    ///     print(result.trimmedStdout)
    /// }
    /// ```
    @discardableResult
    public static func run(
        executable: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        workingDirectory: URL? = nil,
        input: Data? = nil,
        timeout: TimeInterval? = defaultTimeout,
        onLine: (@Sendable (String) -> Void)? = nil,
        isCancelled: (@Sendable () -> Bool)? = nil
    ) -> ProcessResult {
        run(
            executable,
            arguments,
            environment: environment,
            workingDirectory: workingDirectory,
            input: input,
            timeout: timeout,
            onLine: onLine,
            isCancelled: isCancelled
        )
    }

    /// 문자열 경로 작업 디렉터리를 지정하여 외부 프로세스를 직관적으로 실행합니다.
    @discardableResult
    public static func run(
        executable: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        workingDirectoryPath: String?,
        input: Data? = nil,
        timeout: TimeInterval? = defaultTimeout,
        onLine: (@Sendable (String) -> Void)? = nil,
        isCancelled: (@Sendable () -> Bool)? = nil
    ) -> ProcessResult {
        run(
            executable: executable,
            arguments: arguments,
            environment: environment,
            workingDirectory: workingDirectoryPath.map { URL(fileURLWithPath: $0) },
            input: input,
            timeout: timeout,
            onLine: onLine,
            isCancelled: isCancelled
        )
    }

    /// 표준 입력을 문자열로 전달하여 외부 프로세스를 직관적으로 실행합니다.
    @discardableResult
    public static func run(
        executable: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        workingDirectory: URL? = nil,
        inputText: String?,
        timeout: TimeInterval? = defaultTimeout,
        onLine: (@Sendable (String) -> Void)? = nil,
        isCancelled: (@Sendable () -> Bool)? = nil
    ) -> ProcessResult {
        run(
            executable: executable,
            arguments: arguments,
            environment: environment,
            workingDirectory: workingDirectory,
            input: inputText.map { Data($0.utf8) },
            timeout: timeout,
            onLine: onLine,
            isCancelled: isCancelled
        )
    }

    /// 작업 디렉터리 경로와 표준 입력 문자열을 모두 지정하여 외부 프로세스를 실행합니다.
    @discardableResult
    public static func run(
        executable: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        workingDirectoryPath: String?,
        inputText: String?,
        timeout: TimeInterval? = defaultTimeout,
        onLine: (@Sendable (String) -> Void)? = nil,
        isCancelled: (@Sendable () -> Bool)? = nil
    ) -> ProcessResult {
        run(
            executable: executable,
            arguments: arguments,
            environment: environment,
            workingDirectory: workingDirectoryPath.map { URL(fileURLWithPath: $0) },
            input: inputText.map { Data($0.utf8) },
            timeout: timeout,
            onLine: onLine,
            isCancelled: isCancelled
        )
    }

    // MARK: - Explicit Synchronous (runSync)

    /// 명시적 동기 프로세스 실행 메서드.
    @discardableResult
    public static func runSync(
        executable: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        workingDirectory: URL? = nil,
        input: Data? = nil,
        timeout: TimeInterval? = defaultTimeout
    ) -> ProcessResult {
        run(
            executable,
            arguments,
            environment: environment,
            workingDirectory: workingDirectory,
            input: input,
            timeout: timeout
        )
    }

    /// 명시적 동기 프로세스 실행 메서드 (문자열 디렉터리 경로).
    @discardableResult
    public static func runSync(
        executable: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        workingDirectoryPath: String?,
        input: Data? = nil,
        timeout: TimeInterval? = defaultTimeout
    ) -> ProcessResult {
        run(
            executable: executable,
            arguments: arguments,
            environment: environment,
            workingDirectoryPath: workingDirectoryPath,
            input: input,
            timeout: timeout
        )
    }

    /// 명시적 동기 프로세스 실행 메서드 (문자열 표준 입력).
    @discardableResult
    public static func runSync(
        executable: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        workingDirectory: URL? = nil,
        inputText: String?,
        timeout: TimeInterval? = defaultTimeout
    ) -> ProcessResult {
        run(
            executable: executable,
            arguments: arguments,
            environment: environment,
            workingDirectory: workingDirectory,
            inputText: inputText,
            timeout: timeout
        )
    }

    /// 명시적 동기 프로세스 실행 메서드 (문자열 디렉터리 경로 및 표준 입력).
    @discardableResult
    public static func runSync(
        executable: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        workingDirectoryPath: String?,
        inputText: String?,
        timeout: TimeInterval? = defaultTimeout
    ) -> ProcessResult {
        run(
            executable: executable,
            arguments: arguments,
            environment: environment,
            workingDirectoryPath: workingDirectoryPath,
            inputText: inputText,
            timeout: timeout
        )
    }

    /// 명시적 동기 프로세스 실행 메서드 (위치 인자).
    @discardableResult
    public static func runSync(
        _ launchPath: String,
        _ arguments: [String] = [],
        environment: [String: String]? = nil,
        workingDirectory: URL? = nil,
        input: Data? = nil,
        timeout: TimeInterval? = defaultTimeout
    ) -> ProcessResult {
        run(
            launchPath,
            arguments,
            environment: environment,
            workingDirectory: workingDirectory,
            input: input,
            timeout: timeout
        )
    }

    /// 명시적 동기 프로세스 실행 메서드 (명세 기반).
    @discardableResult
    public static func runSync(_ spec: CommandSpecification) -> ProcessResult {
        run(spec)
    }

    /// 동기 실행 후 타임아웃 또는 0이 아닌 종료 코드 시 `ProcessError`를 던집니다.
    @discardableResult
    public static func runSyncThrowing(
        executable: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        workingDirectory: URL? = nil,
        input: Data? = nil,
        timeout: TimeInterval? = defaultTimeout
    ) throws -> ProcessResult {
        let result = runSync(
            executable: executable,
            arguments: arguments,
            environment: environment,
            workingDirectory: workingDirectory,
            input: input,
            timeout: timeout
        )
        if result.timedOut {
            throw CommandError.timedOut(timeout ?? defaultTimeout)
        }
        guard result.ok else {
            throw CommandError.nonZeroExit(exitCode: result.exitCode, stderr: result.stderr)
        }
        return result
    }

    /// 동기 실행 후 타임아웃 또는 0이 아닌 종료 코드 시 `ProcessError`를 던집니다 (문자열 디렉터리 경로).
    @discardableResult
    public static func runSyncThrowing(
        executable: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        workingDirectoryPath: String?,
        input: Data? = nil,
        timeout: TimeInterval? = defaultTimeout
    ) throws -> ProcessResult {
        try runSyncThrowing(
            executable: executable,
            arguments: arguments,
            environment: environment,
            workingDirectory: workingDirectoryPath.map { URL(fileURLWithPath: $0) },
            input: input,
            timeout: timeout
        )
    }

    /// 동기 실행 후 타임아웃 또는 0이 아닌 종료 코드 시 `ProcessError`를 던집니다 (문자열 표준 입력).
    @discardableResult
    public static func runSyncThrowing(
        executable: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        workingDirectory: URL? = nil,
        inputText: String?,
        timeout: TimeInterval? = defaultTimeout
    ) throws -> ProcessResult {
        try runSyncThrowing(
            executable: executable,
            arguments: arguments,
            environment: environment,
            workingDirectory: workingDirectory,
            input: inputText.map { Data($0.utf8) },
            timeout: timeout
        )
    }

    /// 동기 실행 후 타임아웃 또는 0이 아닌 종료 코드 시 `ProcessError`를 던집니다 (문자열 디렉터리 경로 및 표준 입력).
    @discardableResult
    public static func runSyncThrowing(
        executable: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        workingDirectoryPath: String?,
        inputText: String?,
        timeout: TimeInterval? = defaultTimeout
    ) throws -> ProcessResult {
        try runSyncThrowing(
            executable: executable,
            arguments: arguments,
            environment: environment,
            workingDirectory: workingDirectoryPath.map { URL(fileURLWithPath: $0) },
            input: inputText.map { Data($0.utf8) },
            timeout: timeout
        )
    }

    /// 동기 실행 후 타임아웃 또는 0이 아닌 종료 코드 시 `ProcessError`를 던집니다 (위치 인자 스타일).
    @discardableResult
    public static func runSyncThrowing(
        _ launchPath: String,
        _ arguments: [String] = [],
        environment: [String: String]? = nil,
        workingDirectory: URL? = nil,
        input: Data? = nil,
        timeout: TimeInterval? = defaultTimeout
    ) throws -> ProcessResult {
        try runSyncThrowing(
            executable: launchPath,
            arguments: arguments,
            environment: environment,
            workingDirectory: workingDirectory,
            input: input,
            timeout: timeout
        )
    }

    /// 동기 실행 후 타임아웃 또는 0이 아닌 종료 코드 시 `ProcessError`를 던집니다 (명세 기반).
    @discardableResult
    public static func runSyncThrowing(_ spec: CommandSpecification) throws -> ProcessResult {
        let result = runSync(spec)
        if result.timedOut {
            throw CommandError.timedOut(spec.timeout ?? defaultTimeout)
        }
        guard result.ok else {
            throw CommandError.nonZeroExit(exitCode: result.exitCode, stderr: result.stderr)
        }
        return result
    }

    // MARK: - Synchronous Output Extraction (runSyncOutput)

    /// 동기 실행 후 성공 시 trimmed stdout 문자열을 반환하고 실패/타임아웃 시 에러를 던집니다.
    @discardableResult
    public static func runSyncOutput(
        executable: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        workingDirectory: URL? = nil,
        input: Data? = nil,
        timeout: TimeInterval? = defaultTimeout
    ) throws -> String {
        let result = try runSyncThrowing(
            executable: executable,
            arguments: arguments,
            environment: environment,
            workingDirectory: workingDirectory,
            input: input,
            timeout: timeout
        )
        return result.trimmedStdout
    }

    /// 동기 실행 후 성공 시 trimmed stdout 문자열을 반환합니다 (문자열 작업 디렉터리).
    @discardableResult
    public static func runSyncOutput(
        executable: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        workingDirectoryPath: String?,
        input: Data? = nil,
        timeout: TimeInterval? = defaultTimeout
    ) throws -> String {
        try runSyncOutput(
            executable: executable,
            arguments: arguments,
            environment: environment,
            workingDirectory: workingDirectoryPath.map { URL(fileURLWithPath: $0) },
            input: input,
            timeout: timeout
        )
    }

    /// 동기 실행 후 성공 시 trimmed stdout 문자열을 반환합니다 (위치 인자 스타일).
    @discardableResult
    public static func runSyncOutput(
        _ launchPath: String,
        _ arguments: [String] = [],
        timeout: TimeInterval? = defaultTimeout
    ) throws -> String {
        try runSyncOutput(
            executable: launchPath,
            arguments: arguments,
            timeout: timeout
        )
    }

    /// 동기 실행 후 성공 시 trimmed stdout 문자열을 반환합니다 (명세 기반).
    @discardableResult
    public static func runSyncOutput(_ spec: CommandSpecification) throws -> String {
        let result = try runSyncThrowing(spec)
        return result.trimmedStdout
    }

    // MARK: - Asynchronous Execution (runAsync)

    /// 외부 프로세스를 비동기적으로 안전하게 실행합니다 (Non-throwing).
    ///
    /// 협력 스레드 풀 데드락을 방지하고 Swift Structured Concurrency 취소 신호에 반응합니다.
    @discardableResult
    public static func runAsync(
        executable: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        workingDirectory: URL? = nil,
        input: Data? = nil,
        timeout: TimeInterval? = defaultTimeout
    ) async -> ProcessResult {
        #if os(iOS)
        return ProcessResult(stdout: "", stderr: "local command execution is unavailable on iOS", exitCode: 127)
        #else
        let runner = ProcessCommandRunner()
        let spec = CommandSpecification(
            executable,
            arguments,
            environment: environment,
            workingDirectory: workingDirectory,
            input: input,
            timeout: timeout
        )
        return await runner.run(spec)
        #endif
    }

    /// 외부 프로세스를 비동기적으로 안전하게 실행합니다 (문자열 디렉터리 경로).
    @discardableResult
    public static func runAsync(
        executable: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        workingDirectoryPath: String?,
        input: Data? = nil,
        timeout: TimeInterval? = defaultTimeout
    ) async -> ProcessResult {
        await runAsync(
            executable: executable,
            arguments: arguments,
            environment: environment,
            workingDirectory: workingDirectoryPath.map { URL(fileURLWithPath: $0) },
            input: input,
            timeout: timeout
        )
    }

    /// 외부 프로세스를 비동기적으로 안전하게 실행합니다 (문자열 표준 입력).
    @discardableResult
    public static func runAsync(
        executable: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        workingDirectory: URL? = nil,
        inputText: String?,
        timeout: TimeInterval? = defaultTimeout
    ) async -> ProcessResult {
        await runAsync(
            executable: executable,
            arguments: arguments,
            environment: environment,
            workingDirectory: workingDirectory,
            input: inputText.map { Data($0.utf8) },
            timeout: timeout
        )
    }

    /// 외부 프로세스를 비동기적으로 안전하게 실행합니다 (위치 인자, Non-throwing).
    @discardableResult
    public static func runAsync(
        _ launchPath: String,
        _ arguments: [String] = [],
        environment: [String: String]? = nil,
        workingDirectory: URL? = nil,
        input: Data? = nil,
        timeout: TimeInterval? = defaultTimeout
    ) async -> ProcessResult {
        await runAsync(
            executable: launchPath,
            arguments: arguments,
            environment: environment,
            workingDirectory: workingDirectory,
            input: input,
            timeout: timeout
        )
    }

    /// `CommandSpecification` 명세에 따라 프로세스를 비동기적으로 실행합니다.
    @discardableResult
    public static func runAsync(_ spec: CommandSpecification) async -> ProcessResult {
        #if os(iOS)
        return ProcessResult(stdout: "", stderr: "local command execution is unavailable on iOS", exitCode: 127)
        #else
        let runner = ProcessCommandRunner()
        return await runner.run(spec)
        #endif
    }

    // MARK: - Asynchronous Throwing (async throws -> ProcessResult)

    /// 비동기 프로세스 실행 표준 API (실패/타임아웃 시 throws).
    ///
    /// ```swift
    /// do {
    ///     let result = try await SafeProcessRunner.run(executable: "/bin/sh", arguments: ["-c", "whoami"])
    ///     print("User:", result.trimmedStdout)
    /// } catch {
    ///     print("Failed:", error)
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - executable: 실행 바이너리 경로
    ///   - arguments: 명령행 인자 목록
    ///   - environment: 재정의할 환경 변수 맵 (선택사항)
    ///   - workingDirectory: 작업 디렉터리 URL (선택사항)
    ///   - input: 표준 입력 데이터 (선택사항)
    ///   - timeout: 타임아웃(초 단위, 기본 30초)
    ///   - throwOnNonZeroExit: exit code != 0 일 때 `CommandError.nonZeroExit`를 던질지 여부 (기본 true)
    /// - Returns: 실행 결과 (`ProcessResult`).
    @discardableResult
    public static func run(
        executable: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        workingDirectory: URL? = nil,
        input: Data? = nil,
        timeout: TimeInterval? = defaultTimeout,
        throwOnNonZeroExit: Bool = true
    ) async throws -> ProcessResult {
        #if os(iOS)
        throw CommandError.launchFailed("local command execution is unavailable on iOS")
        #else
        try Task.checkCancellation()
        let result = await runAsync(
            executable: executable,
            arguments: arguments,
            environment: environment,
            workingDirectory: workingDirectory,
            input: input,
            timeout: timeout
        )
        try Task.checkCancellation()
        if result.timedOut {
            throw CommandError.timedOut(timeout ?? defaultTimeout)
        }
        if result.exitCode == 127 && (result.stderr.contains("No such file") || result.stderr.contains("not found") || result.stderr.contains("failed to launch")) {
            throw CommandError.launchFailed(result.stderr)
        }
        if throwOnNonZeroExit && !result.ok {
            throw CommandError.nonZeroExit(exitCode: result.exitCode, stderr: result.stderr)
        }
        return result
        #endif
    }

    /// 비동기 프로세스 실행 (문자열 디렉터리 경로, throws).
    @discardableResult
    public static func run(
        executable: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        workingDirectoryPath: String?,
        input: Data? = nil,
        timeout: TimeInterval? = defaultTimeout,
        throwOnNonZeroExit: Bool = true
    ) async throws -> ProcessResult {
        try await run(
            executable: executable,
            arguments: arguments,
            environment: environment,
            workingDirectory: workingDirectoryPath.map { URL(fileURLWithPath: $0) },
            input: input,
            timeout: timeout,
            throwOnNonZeroExit: throwOnNonZeroExit
        )
    }

    /// 비동기 프로세스 실행 (문자열 표준 입력, throws).
    @discardableResult
    public static func run(
        executable: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        workingDirectory: URL? = nil,
        inputText: String?,
        timeout: TimeInterval? = defaultTimeout,
        throwOnNonZeroExit: Bool = true
    ) async throws -> ProcessResult {
        try await run(
            executable: executable,
            arguments: arguments,
            environment: environment,
            workingDirectory: workingDirectory,
            input: inputText.map { Data($0.utf8) },
            timeout: timeout,
            throwOnNonZeroExit: throwOnNonZeroExit
        )
    }

    /// 비동기 프로세스 실행 (문자열 디렉터리 경로 및 표준 입력, throws).
    @discardableResult
    public static func run(
        executable: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        workingDirectoryPath: String?,
        inputText: String?,
        timeout: TimeInterval? = defaultTimeout,
        throwOnNonZeroExit: Bool = true
    ) async throws -> ProcessResult {
        try await run(
            executable: executable,
            arguments: arguments,
            environment: environment,
            workingDirectory: workingDirectoryPath.map { URL(fileURLWithPath: $0) },
            input: inputText.map { Data($0.utf8) },
            timeout: timeout,
            throwOnNonZeroExit: throwOnNonZeroExit
        )
    }

    /// 비동기 프로세스 실행 (위치 인자 스타일, throws).
    @discardableResult
    public static func run(
        _ launchPath: String,
        _ arguments: [String] = [],
        environment: [String: String]? = nil,
        workingDirectory: URL? = nil,
        input: Data? = nil,
        timeout: TimeInterval? = defaultTimeout,
        throwOnNonZeroExit: Bool = true
    ) async throws -> ProcessResult {
        try await run(
            executable: launchPath,
            arguments: arguments,
            environment: environment,
            workingDirectory: workingDirectory,
            input: input,
            timeout: timeout,
            throwOnNonZeroExit: throwOnNonZeroExit
        )
    }

    /// 비동기 프로세스 실행 (명세 기반, throws).
    @discardableResult
    public static func run(
        _ spec: CommandSpecification,
        throwOnNonZeroExit: Bool = true
    ) async throws -> ProcessResult {
        try await run(
            executable: spec.launchPath,
            arguments: spec.arguments,
            environment: spec.environment,
            workingDirectory: spec.workingDirectory,
            input: spec.input,
            timeout: spec.timeout,
            throwOnNonZeroExit: throwOnNonZeroExit
        )
    }

    /// 비동기 프로세스 실행 후 실패 시 명시적으로 throw하는 편의 메서드.
    @discardableResult
    public static func runThrowing(
        executable: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        workingDirectory: URL? = nil,
        input: Data? = nil,
        timeout: TimeInterval? = defaultTimeout
    ) async throws -> ProcessResult {
        try await run(
            executable: executable,
            arguments: arguments,
            environment: environment,
            workingDirectory: workingDirectory,
            input: input,
            timeout: timeout,
            throwOnNonZeroExit: true
        )
    }

    /// 비동기 프로세스 실행 후 실패 시 명시적으로 throw하는 편의 메서드 (문자열 디렉터리 경로).
    @discardableResult
    public static func runThrowing(
        executable: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        workingDirectoryPath: String?,
        input: Data? = nil,
        timeout: TimeInterval? = defaultTimeout
    ) async throws -> ProcessResult {
        try await runThrowing(
            executable: executable,
            arguments: arguments,
            environment: environment,
            workingDirectory: workingDirectoryPath.map { URL(fileURLWithPath: $0) },
            input: input,
            timeout: timeout
        )
    }

    /// 비동기 프로세스 실행 후 실패 시 명시적으로 throw하는 편의 메서드 (문자열 표준 입력).
    @discardableResult
    public static func runThrowing(
        executable: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        workingDirectory: URL? = nil,
        inputText: String?,
        timeout: TimeInterval? = defaultTimeout
    ) async throws -> ProcessResult {
        try await runThrowing(
            executable: executable,
            arguments: arguments,
            environment: environment,
            workingDirectory: workingDirectory,
            input: inputText.map { Data($0.utf8) },
            timeout: timeout
        )
    }

    /// 비동기 프로세스 실행 후 실패 시 명시적으로 throw하는 편의 메서드 (위치 인자 스타일).
    @discardableResult
    public static func runThrowing(
        _ launchPath: String,
        _ arguments: [String] = [],
        environment: [String: String]? = nil,
        workingDirectory: URL? = nil,
        input: Data? = nil,
        timeout: TimeInterval? = defaultTimeout
    ) async throws -> ProcessResult {
        try await run(
            executable: launchPath,
            arguments: arguments,
            environment: environment,
            workingDirectory: workingDirectory,
            input: input,
            timeout: timeout,
            throwOnNonZeroExit: true
        )
    }

    /// 비동기 프로세스 실행 후 실패 시 명시적으로 throw하는 편의 메서드 (명세 기반).
    @discardableResult
    public static func runThrowing(
        _ spec: CommandSpecification
    ) async throws -> ProcessResult {
        try await run(spec, throwOnNonZeroExit: true)
    }

    // MARK: - Asynchronous Output Extraction (runOutput)

    /// 비동기 실행 후 성공 시 trimmed stdout 문자열을 반환하고 실패/타임아웃 시 에러를 던집니다.
    @discardableResult
    public static func runOutput(
        executable: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        workingDirectory: URL? = nil,
        input: Data? = nil,
        timeout: TimeInterval? = defaultTimeout
    ) async throws -> String {
        let result = try await run(
            executable: executable,
            arguments: arguments,
            environment: environment,
            workingDirectory: workingDirectory,
            input: input,
            timeout: timeout,
            throwOnNonZeroExit: true
        )
        return result.trimmedStdout
    }

    /// 비동기 실행 후 성공 시 trimmed stdout 문자열을 반환합니다 (문자열 디렉터리 경로).
    @discardableResult
    public static func runOutput(
        executable: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        workingDirectoryPath: String?,
        input: Data? = nil,
        timeout: TimeInterval? = defaultTimeout
    ) async throws -> String {
        try await runOutput(
            executable: executable,
            arguments: arguments,
            environment: environment,
            workingDirectory: workingDirectoryPath.map { URL(fileURLWithPath: $0) },
            input: input,
            timeout: timeout
        )
    }

    /// 비동기 실행 후 성공 시 trimmed stdout 문자열을 반환합니다 (위치 인자 스타일).
    @discardableResult
    public static func runOutput(
        _ launchPath: String,
        _ arguments: [String] = [],
        timeout: TimeInterval? = defaultTimeout
    ) async throws -> String {
        try await runOutput(
            executable: launchPath,
            arguments: arguments,
            timeout: timeout
        )
    }

    /// 비동기 실행 후 성공 시 trimmed stdout 문자열을 반환합니다 (명세 기반).
    @discardableResult
    public static func runOutput(_ spec: CommandSpecification) async throws -> String {
        let result = try await run(spec, throwOnNonZeroExit: true)
        return result.trimmedStdout
    }

    // MARK: - Shell Helpers

    /// 셸 커맨드 문자열을 안전하게 동기 실행합니다.
    @discardableResult
    public static func runShell(
        _ command: String,
        environment: [String: String]? = nil,
        workingDirectory: URL? = nil,
        input: Data? = nil,
        timeout: TimeInterval? = defaultTimeout
    ) -> ProcessResult {
        run(
            "/bin/sh",
            ["-c", command],
            environment: environment,
            workingDirectory: workingDirectory,
            input: input,
            timeout: timeout
        )
    }

    /// 셸 커맨드 문자열을 안전하게 비동기 실행합니다.
    @discardableResult
    public static func runShellAsync(
        _ command: String,
        environment: [String: String]? = nil,
        workingDirectory: URL? = nil,
        input: Data? = nil,
        timeout: TimeInterval? = defaultTimeout
    ) async -> ProcessResult {
        await runAsync(
            executable: "/bin/sh",
            arguments: ["-c", command],
            environment: environment,
            workingDirectory: workingDirectory,
            input: input,
            timeout: timeout
        )
    }

    /// 셸 커맨드 문자열을 비동기 실행하고 실패 시 throw합니다.
    @discardableResult
    public static func runShell(
        _ command: String,
        environment: [String: String]? = nil,
        workingDirectory: URL? = nil,
        input: Data? = nil,
        timeout: TimeInterval? = defaultTimeout,
        throwOnNonZeroExit: Bool = true
    ) async throws -> ProcessResult {
        try await run(
            executable: "/bin/sh",
            arguments: ["-c", command],
            environment: environment,
            workingDirectory: workingDirectory,
            input: input,
            timeout: timeout,
            throwOnNonZeroExit: throwOnNonZeroExit
        )
    }

    /// 셸 커맨드 문자열을 동기 실행하고 trimmed stdout 문자열을 반환합니다.
    @discardableResult
    public static func runShellSyncOutput(
        _ command: String,
        environment: [String: String]? = nil,
        workingDirectory: URL? = nil,
        timeout: TimeInterval? = defaultTimeout
    ) throws -> String {
        let result = runShell(
            command,
            environment: environment,
            workingDirectory: workingDirectory,
            timeout: timeout
        )
        if result.timedOut {
            throw CommandError.timedOut(timeout ?? defaultTimeout)
        }
        guard result.ok else {
            throw CommandError.nonZeroExit(exitCode: result.exitCode, stderr: result.stderr)
        }
        return result.trimmedStdout
    }

    /// 셸 커맨드 문자열을 비동기 실행하고 trimmed stdout 문자열을 반환합니다.
    @discardableResult
    public static func runShellOutput(
        _ command: String,
        environment: [String: String]? = nil,
        workingDirectory: URL? = nil,
        timeout: TimeInterval? = defaultTimeout
    ) async throws -> String {
        let result = try await runShell(
            command,
            environment: environment,
            workingDirectory: workingDirectory,
            timeout: timeout,
            throwOnNonZeroExit: true
        )
        return result.trimmedStdout
    }

    // MARK: - Process Spawning

    /// 생명주기 추적이 필요한 자식 프로세스를 스폰합니다.
    ///
    /// 일반 실행은 `run`/`runAsync`를 사용하세요. 워커 수거 등 자식의 pid 생명주기를 직접 검증해야 하는 경우에만 사용합니다.
    public static func spawn(
        _ launchPath: String,
        _ arguments: [String] = [],
        environment: [String: String]? = nil,
        workingDirectory: URL? = nil,
        standardOutput: Any? = nil,
        standardError: Any? = nil
    ) throws -> RunningProcess {
        try CommandKitSync.spawn(
            launchPath,
            arguments,
            environment: environment,
            workingDirectory: workingDirectory,
            standardOutput: standardOutput,
            standardError: standardError
        )
    }

    /// 생명주기 추적이 필요한 자식 프로세스를 레이블 인자로 스폰합니다.
    public static func spawn(
        executable: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        workingDirectory: URL? = nil,
        standardOutput: Any? = nil,
        standardError: Any? = nil
    ) throws -> RunningProcess {
        try spawn(
            executable,
            arguments,
            environment: environment,
            workingDirectory: workingDirectory,
            standardOutput: standardOutput,
            standardError: standardError
        )
    }

    // MARK: - Streaming (lines)

    /// 명령 실행의 라인별 출력을 비동기 스트림으로 제공합니다.
    public static func lines(_ spec: CommandSpecification) -> AsyncThrowingStream<CommandLineOutput, Error> {
        #if os(iOS)
        return AsyncThrowingStream { continuation in
            continuation.finish(throwing: CommandError.launchFailed("local command execution is unavailable on iOS"))
        }
        #else
        return ProcessCommandRunner().lines(spec)
        #endif
    }

    /// 명령 실행의 라인별 출력을 비동기 스트림으로 제공합니다 (레이블 인자).
    public static func lines(
        executable: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        workingDirectory: URL? = nil,
        timeout: TimeInterval? = nil
    ) -> AsyncThrowingStream<CommandLineOutput, Error> {
        lines(CommandSpecification(
            executable,
            arguments,
            environment: environment,
            workingDirectory: workingDirectory,
            timeout: timeout
        ))
    }

    // MARK: - CommandRunning Protocol Conformance & Instance Ergonomics

    public func run(_ spec: CommandSpecification) async -> ProcessResult {
        await Self.runAsync(spec)
    }

    public func lines(_ spec: CommandSpecification) -> AsyncThrowingStream<CommandLineOutput, Error> {
        Self.lines(spec)
    }

    public func run(_ launchPath: String, _ arguments: [String], timeout: TimeInterval?) async -> ProcessResult {
        await Self.runAsync(launchPath, arguments, timeout: timeout)
    }

    @discardableResult
    public func runAsync(
        executable: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        workingDirectory: URL? = nil,
        input: Data? = nil,
        timeout: TimeInterval? = Self.defaultTimeout
    ) async -> ProcessResult {
        await Self.runAsync(
            executable: executable,
            arguments: arguments,
            environment: environment,
            workingDirectory: workingDirectory,
            input: input,
            timeout: timeout
        )
    }

    @discardableResult
    public func run(
        executable: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        workingDirectory: URL? = nil,
        input: Data? = nil,
        timeout: TimeInterval? = Self.defaultTimeout,
        throwOnNonZeroExit: Bool = true
    ) async throws -> ProcessResult {
        try await Self.run(
            executable: executable,
            arguments: arguments,
            environment: environment,
            workingDirectory: workingDirectory,
            input: input,
            timeout: timeout,
            throwOnNonZeroExit: throwOnNonZeroExit
        )
    }

    @discardableResult
    public func runThrowing(
        executable: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        workingDirectory: URL? = nil,
        input: Data? = nil,
        timeout: TimeInterval? = Self.defaultTimeout
    ) async throws -> ProcessResult {
        try await run(
            executable: executable,
            arguments: arguments,
            environment: environment,
            workingDirectory: workingDirectory,
            input: input,
            timeout: timeout,
            throwOnNonZeroExit: true
        )
    }

    @discardableResult
    public func runSync(
        executable: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        workingDirectory: URL? = nil,
        input: Data? = nil,
        timeout: TimeInterval? = Self.defaultTimeout
    ) -> ProcessResult {
        Self.runSync(
            executable: executable,
            arguments: arguments,
            environment: environment,
            workingDirectory: workingDirectory,
            input: input,
            timeout: timeout
        )
    }

    @discardableResult
    public func runOutput(
        executable: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        workingDirectory: URL? = nil,
        input: Data? = nil,
        timeout: TimeInterval? = Self.defaultTimeout
    ) async throws -> String {
        try await Self.runOutput(
            executable: executable,
            arguments: arguments,
            environment: environment,
            workingDirectory: workingDirectory,
            input: input,
            timeout: timeout
        )
    }

    // MARK: - Safe Process Termination & Group Management (no-unsafe-process-kill 방어)

    /// 단일 대상 프로세스에 안전하게 시그널을 전달합니다.
    ///
    /// - Important: `pid <= 1` (0: 현재 프로세스 그룹 전체, -1: 전체 시스템 프로세스, 1: init)는
    ///   호출자 자살 및 시스템 중단을 방지하기 위해 엄격히 차단됩니다.
    /// - Parameters:
    ///   - pid: 종료 대상 프로세스 식별자 (반드시 > 1).
    ///   - signal: 전송할 POSIX 시그널 (기본값: `SIGTERM`).
    /// - Returns: 시그널 전달 성공 여부 (대상 미존재 시 false).
    @discardableResult
    public static func killProcess(pid: pid_t, signal: Int32 = SIGTERM) -> Bool {
        #if os(iOS)
        return false
        #elseif canImport(Darwin) || canImport(Glibc)
        guard pid > 1 else { return false }
        return kill(pid, signal) == 0
        #else
        return false
        #endif
    }

    /// 분리된 프로세스 그룹(Process Group)에 안전하게 시그널을 전달합니다.
    ///
    /// - Important: 위험한 `kill(-pid)` 대신 POSIX `killpg`를 사용하며, 호출자 자신의 프로세스 그룹(`getpgrp()`)과
    ///   동일한 경우 호출자 자살을 방지하기 위해 즉시 거부합니다.
    /// - Parameters:
    ///   - pgid: 종료 대상 프로세스 그룹 식별자 (반드시 > 1).
    ///   - signal: 전송할 POSIX 시그널 (기본값: `SIGTERM`).
    /// - Returns: 시그널 전달 성공 여부.
    @discardableResult
    public static func killProcessGroup(pgid: pid_t, signal: Int32 = SIGTERM) -> Bool {
        #if os(iOS)
        return false
        #elseif canImport(Darwin) || canImport(Glibc)
        guard pgid > 1 else { return false }
        let currentPgid = getpgrp()
        guard pgid != currentPgid else {
            // 호출자 자신의 프로세스 그룹을 죽이려는 자살 호출 차단
            return false
        }
        return killpg(pgid, signal) == 0
        #else
        return false
        #endif
    }

    /// 대상 프로세스가 여전히 살아있는지 확인합니다 (signal 0 probe).
    public static func isProcessAlive(pid: pid_t) -> Bool {
        #if os(iOS)
        return false
        #elseif canImport(Darwin) || canImport(Glibc)
        guard pid > 1 else { return false }
        return kill(pid, 0) == 0
        #else
        return false
        #endif
    }

    /// 대상 프로세스 그룹이 여전히 존재하는지 확인합니다.
    public static func isProcessGroupAlive(pgid: pid_t) -> Bool {
        #if os(iOS)
        return false
        #elseif canImport(Darwin) || canImport(Glibc)
        guard pgid > 1 else { return false }
        let currentPgid = getpgrp()
        guard pgid != currentPgid else { return true }
        return killpg(pgid, 0) == 0
        #else
        return false
        #endif
    }

    /// 단일 프로세스를 단계적(SIGTERM -> gracePeriod -> SIGKILL)으로 안전하게 종료합니다.
    @discardableResult
    public static func terminateProcess(
        pid: pid_t,
        gracePeriod: TimeInterval = 1.5
    ) async -> Bool {
        guard killProcess(pid: pid, signal: SIGTERM) else {
            return false
        }
        guard isProcessAlive(pid: pid) else { return true }

        do {
            try await Task.sleep(nanoseconds: UInt64(gracePeriod * 1_000_000_000))
        } catch {}

        if isProcessAlive(pid: pid) {
            _ = killProcess(pid: pid, signal: SIGKILL)
        }
        return !isProcessAlive(pid: pid)
    }

    /// 프로세스 그룹을 단계적(SIGTERM -> gracePeriod -> SIGKILL)으로 안전하게 종료합니다.
    @discardableResult
    public static func terminateProcessGroup(
        pgid: pid_t,
        gracePeriod: TimeInterval = 1.5
    ) async -> Bool {
        guard killProcessGroup(pgid: pgid, signal: SIGTERM) else {
            return false
        }
        guard isProcessGroupAlive(pgid: pgid) else { return true }

        do {
            try await Task.sleep(nanoseconds: UInt64(gracePeriod * 1_000_000_000))
        } catch {}

        if isProcessGroupAlive(pgid: pgid) {
            _ = killProcessGroup(pgid: pgid, signal: SIGKILL)
        }
        return !isProcessGroupAlive(pgid: pgid)
    }

    /// Foundation.Process 인스턴스를 단계적으로 안전하게 종료합니다.
    public static func terminate(
        _ process: Process,
        gracePeriod: TimeInterval = 1.5
    ) async {
        let pid = process.processIdentifier
        process.terminate()
        guard pid > 1 && process.isRunning else { return }

        do {
            try await Task.sleep(nanoseconds: UInt64(gracePeriod * 1_000_000_000))
        } catch {}

        if process.isRunning && isProcessAlive(pid: pid) {
            _ = killProcess(pid: pid, signal: SIGKILL)
        }
    }
}
