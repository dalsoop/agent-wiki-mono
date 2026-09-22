import Foundation
import CommandKit
import PrivilegedExec
#if canImport(Darwin)
import Darwin
#endif

/// root 권한이 필요한 명령을 Security.framework 프롬프트로 실행한다.
/// 여러 명령은 한 번의 프롬프트로 배치 실행해 프롬프트 빈도를 줄인다.
///
/// 라이브 경로는 `AuthorizationExecuteWithPrivileges`(deprecated, 암호 대화상자는 유지).
/// 주입된 `CommandRunning` 목은 `/bin/sh -c` 로 관측한다.
///
/// 결과 의미:
/// - 사용자가 암호 프롬프트를 취소하면 stderr 에 "User canceled", exit code 는
///   `errAuthorizationCanceled`(-60006) 근처다.
/// - `&&` 배치는 fail-fast 라, 중간 명령이 실패하면 어느 단계에서 멈췄는지는 불투명하다.
public struct PrivilegedRunner: Sendable {
    private let runner: CommandRunning

    public init(runner: CommandRunning = ProcessCommandRunner()) {
        self.runner = runner
    }

    public func run(_ shellCommand: String) async -> CommandResult {
        await run([shellCommand])
    }

    /// `run` 과 같다. 소비처가 권한 실행임을 이름에 드러내고 싶을 때 쓴다.
    public func executeAuthorized(_ shellCommands: [String]) async -> CommandResult {
        await run(shellCommands)
    }

    /// 동기 관리자 실행. GUI 암호 대화상자가 현재 스레드에서 뜬다.
    @discardableResult
    public static func executeAuthorized(_ shellCommand: String) -> CommandResult {
        if geteuid() == 0 {
            return runShellSync(shellCommand)
        }
        return executeWithAuthorization(shellCommand)
    }

    /// 여러 셸 명령을 `&&` 로 이어 한 번의 관리자 프롬프트로 실행.
    /// 각 명령은 호출자가 신뢰하는 하드코딩 문자열이어야 한다 — 사용자 입력을 직접 전달하지 말 것.
    /// 이미 root 로 실행 중이면(sudo CLI 등) 프롬프트 없이 바로 실행한다.
    public func run(_ shellCommands: [String]) async -> CommandResult {
        guard !shellCommands.isEmpty else {
            return CommandResult(stdout: "", stderr: "PrivilegedRunner.run called with empty commands", exitCode: 1)
        }
        let joined = shellCommands.joined(separator: " && ")
        if geteuid() == 0 {
            return await runner.run("/bin/sh", ["-c", joined])
        }
        if runner is ProcessCommandRunner {
            return await Task.detached {
                Self.executeWithAuthorization(joined)
            }.value
        }
        return await runner.run("/bin/sh", ["-c", joined])
    }

    /// 실행 경로 선택 (순수 함수 — 단위테스트 대상). 셸 직행.
    public static func invocation(for shellCommands: [String], asRoot: Bool) -> (String, [String]) {
        _ = asRoot
        return ("/bin/sh", ["-c", shellCommands.joined(separator: " && ")])
    }

    private static func runShellSync(_ command: String) -> CommandResult {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", command]
        let out = Pipe()
        let err = Pipe()
        p.standardOutput = out
        p.standardError = err
        do { try p.run() } catch {
            return CommandResult(stdout: "", stderr: error.localizedDescription, exitCode: 1)
        }
        p.waitUntilExit()
        let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return CommandResult(stdout: stdout, stderr: stderr, exitCode: p.terminationStatus)
    }

    private static func executeWithAuthorization(_ command: String) -> CommandResult {
        #if os(macOS)
        var outPtr: UnsafeMutablePointer<CChar>?
        var errPtr: UnsafeMutablePointer<CChar>?
        let code = command.withCString { cmd in
            PrivilegedExecRun(cmd, &outPtr, &errPtr)
        }
        defer {
            if let p = outPtr { free(p) }
            if let p = errPtr { free(p) }
        }
        let stdout = outPtr.map { String(cString: $0) } ?? ""
        let stderr = errPtr.map { String(cString: $0) } ?? ""
        return CommandResult(stdout: stdout, stderr: stderr, exitCode: Int32(code))
        #else
        return CommandResult(stdout: "", stderr: "privileged exec is macOS-only", exitCode: 1)
        #endif
    }
}
