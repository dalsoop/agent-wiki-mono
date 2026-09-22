import Foundation

/// 외부 프로세스 실행 결과.
public struct CommandResult: Sendable, Equatable {
    public let stdout: String
    public let stderr: String
    public let exitCode: Int32
    public let timedOut: Bool

    public init(stdout: String, stderr: String, exitCode: Int32) {
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
        self.timedOut = false
    }

    public init(stdout: String, stderr: String, exitCode: Int32, timedOut: Bool) {
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
        self.timedOut = timedOut
    }

    /// exit code 0 이면 성공.
    public var ok: Bool { exitCode == 0 && !timedOut }

    /// 실행 성공 여부 (`ok` 와 동일).
    public var isSuccess: Bool { ok }

    /// 앞뒤 공백 제거한 stdout.
    public var trimmedStdout: String {
        stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 앞뒤 공백 제거한 stderr.
    public var trimmedStderr: String {
        stderr.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// stdout 과 stderr 를 결합한 전체 출력.
    public var combinedOutput: String {
        stdout + stderr
    }

    /// stdout 을 UTF-8 인코딩 Data 로 변환한 값.
    public var stdoutData: Data {
        Data(stdout.utf8)
    }

    /// stderr 를 UTF-8 인코딩 Data 로 변환한 값.
    public var stderrData: Data {
        Data(stderr.utf8)
    }

    /// stdout 을 개행 기준으로 분리한 라인 목록.
    public var lines: [String] {
        stdout.components(separatedBy: "\n")
    }

    /// stdout 을 개행 기준으로 분리하고 공백 라인을 제거한 라인 목록.
    public var nonEmptyLines: [String] {
        stdout
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

/// Core 레이어 표준 프로세스 실행 결과 타입 alias.
public typealias ProcessResult = CommandResult

/// Core 레이어 표준 프로세스 에러 타입 alias.
public typealias ProcessError = CommandError
