import Foundation
import CommandKit

/// 외부 프로세스 실행 결과.
public struct TestProcessResult: Sendable, Equatable {
    /// 프로세스 종료 상태 코드 (타임아웃 시 124 등).
    public let exitCode: Int32
    /// 표준 출력 문자열.
    public let stdout: String
    /// 표준 에러 문자열.
    public let stderr: String
    /// 프로세스 실행 경과 시간(초 단위).
    public let duration: TimeInterval
    /// 타임아웃 발생 여부.
    public let timedOut: Bool

    public init(
        exitCode: Int32,
        stdout: String,
        stderr: String,
        duration: TimeInterval,
        timedOut: Bool = false
    ) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.duration = duration
        self.timedOut = timedOut
    }

    /// 실행 성공 여부 (exitCode == 0 이고 타임아웃되지 않음).
    public var isSuccess: Bool {
        exitCode == 0 && !timedOut
    }

    /// 표준 출력과 표준 에러를 합친 문자열.
    public var combinedOutput: String {
        stdout + stderr
    }

    /// 좌우 공백 및 개행이 제거된 표준 출력.
    public var trimmedStdout: String {
        stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 좌우 공백 및 개행이 제거된 표준 에러.
    public var trimmedStderr: String {
        stderr.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// 테스트 코드에서 날것의 `Process()` 생성을 대체하는 안전한 테스트 프로세스 러너.
///
/// - 64KB 파이프 버퍼 초과로 인한 데드락 방지
/// - 타임아웃(기본 10초) 강제 적용
/// - 동기(`run`) 및 비동기(`runAsync`) 실행 지원
public enum TestProcessRunner {
    /// 기본 타임아웃 (10.0초).
    public static let defaultTimeout: TimeInterval = 10.0

    /// 외부 프로세스를 동기적으로 안전하게 실행합니다.
    ///
    /// - Parameters:
    ///   - executable: 실행할 바이너리 경로 (예: `/bin/sh`, `/bin/echo` 등).
    ///   - arguments: 전달할 명령행 인자 목록.
    ///   - environment: 재정의할 환경 변수 맵 (선택사항).
    ///   - workingDirectory: 작업 디렉터리 URL (선택사항).
    ///   - input: 표준 입력(stdin)으로 전달할 데이터 (선택사항).
    ///   - timeout: 타임아웃(초 단위, 기본 10초).
    /// - Returns: 실행 결과(`TestProcessResult`).
    @discardableResult
    public static func run(
        executable: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        workingDirectory: URL? = nil,
        input: Data? = nil,
        timeout: TimeInterval = defaultTimeout
    ) -> TestProcessResult {
        let start = DispatchTime.now().uptimeNanoseconds
        #if os(iOS)
        let duration = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000.0
        return TestProcessResult(
            exitCode: 127,
            stdout: "",
            stderr: "local command execution is unavailable on iOS",
            duration: duration,
            timedOut: false
        )
        #else
        let result = CommandKit.SafeProcessRunner.run(
            executable,
            arguments,
            environment: environment,
            workingDirectory: workingDirectory,
            input: input,
            timeout: timeout
        )
        let duration = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000.0
        return TestProcessResult(
            exitCode: result.exitCode,
            stdout: result.stdout,
            stderr: result.stderr,
            duration: duration,
            timedOut: result.timedOut
        )
        #endif
    }

    /// 외부 프로세스를 비동기적으로 안전하게 실행합니다.
    ///
    /// - Parameters:
    ///   - executable: 실행할 바이너리 경로.
    ///   - arguments: 전달할 명령행 인자 목록.
    ///   - environment: 재정의할 환경 변수 맵 (선택사항).
    ///   - workingDirectory: 작업 디렉터리 URL (선택사항).
    ///   - input: 표준 입력(stdin)으로 전달할 데이터 (선택사항).
    ///   - timeout: 타임아웃(초 단위, 기본 10초).
    /// - Returns: 실행 결과(`TestProcessResult`).
    @discardableResult
    public static func runAsync(
        executable: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        workingDirectory: URL? = nil,
        input: Data? = nil,
        timeout: TimeInterval = defaultTimeout
    ) async -> TestProcessResult {
        let start = DispatchTime.now().uptimeNanoseconds
        #if os(iOS)
        let duration = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000.0
        return TestProcessResult(
            exitCode: 127,
            stdout: "",
            stderr: "local command execution is unavailable on iOS",
            duration: duration,
            timedOut: false
        )
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
        let result = await runner.run(spec)
        let duration = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000.0
        return TestProcessResult(
            exitCode: result.exitCode,
            stdout: result.stdout,
            stderr: result.stderr,
            duration: duration,
            timedOut: result.timedOut
        )
        #endif
    }

    /// 셸 커맨드 라인을 안전하게 실행하는 편의 메서드.
    @discardableResult
    public static func runShell(
        _ command: String,
        environment: [String: String]? = nil,
        workingDirectory: URL? = nil,
        input: Data? = nil,
        timeout: TimeInterval = defaultTimeout
    ) -> TestProcessResult {
        run(
            executable: "/bin/sh",
            arguments: ["-c", command],
            environment: environment,
            workingDirectory: workingDirectory,
            input: input,
            timeout: timeout
        )
    }

    /// 셸 커맨드 라인을 비동기적으로 안전하게 실행하는 편의 메서드.
    @discardableResult
    public static func runShellAsync(
        _ command: String,
        environment: [String: String]? = nil,
        workingDirectory: URL? = nil,
        input: Data? = nil,
        timeout: TimeInterval = defaultTimeout
    ) async -> TestProcessResult {
        await runAsync(
            executable: "/bin/sh",
            arguments: ["-c", command],
            environment: environment,
            workingDirectory: workingDirectory,
            input: input,
            timeout: timeout
        )
    }
}
