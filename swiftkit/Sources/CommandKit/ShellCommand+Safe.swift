#if !os(iOS)
import Foundation

/// ShellCommand 실행 실패 상세 에러.
public enum ShellCommandError: LocalizedError, Equatable, Sendable {
    case executionFailed(command: String, exitCode: Int32, stderr: String)

    public var errorDescription: String? {
        switch self {
        case .executionFailed(let command, let exitCode, let stderr):
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return "ShellCommand failed (exit \(exitCode)): \(command)\(detail.isEmpty ? "" : " - \(detail)")"
        }
    }
}

extension ShellCommand {
    public static let defaultSafeTimeout: TimeInterval = 30.0

    /// 안전한 셸 명령 실행 (기본 defaultSafeTimeout 타임아웃, 비정상 종료 코드 시 ShellCommandError throw).
    /// 날것의 Process()나 셸 인젝션, 무한 행을 방지하는 골든 스탠다드 SSOT.
    @discardableResult
    public static func runSafe(
        _ command: String,
        cwd: String? = nil,
        input: Data? = nil,
        timeout: TimeInterval? = defaultSafeTimeout
    ) throws -> CommandResult {
        let result = run(command, cwd: cwd, input: input, timeout: timeout)
        guard result.ok else {
            throw ShellCommandError.executionFailed(
                command: command,
                exitCode: result.exitCode,
                stderr: result.stderr
            )
        }
        return result
    }
}
#endif
