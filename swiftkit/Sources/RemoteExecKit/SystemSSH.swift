import Foundation
import CommandKit

/// system `ssh` 실행 실패 모드. (앱이 자기 도메인 에러로 매핑해 쓸 수 있게 공용 제공)
public enum SSHExecError: Error, Equatable, Sendable {
    case authFailure(String)
    case unreachable(String)
    case commandFailed(String)
    case noCredentials
}

/// ssh stderr 로 인증/host-key 실패(vs 네트워크)를 구분하는 휴리스틱.
public enum SSHAuth {
    public static func isAuthFailure(_ stderr: String) -> Bool {
        let s = stderr.lowercased()
        return s.contains("permission denied")
            || s.contains("host key verification failed")
            || s.contains("no supported authentication")
    }
}

/// `/usr/bin/ssh` 를 키 기반(BatchMode — 비밀번호 프롬프트 없음)으로 돌려 원격 명령을 실행하는
/// 얇은 러너. 실제 프로세스 실행·동시 파이프 드레인은 CommandKit `ProcessCommandRunner` 에 위임한다.
/// proxmox-monitor 등 각 앱이 손으로 짠 system-ssh 실행부의 정본.
public struct SystemSSHClient: Sendable {
    public var connectTimeout: Int
    public var strictHostKeyChecking: String
    public var controlMaster: SSHControlMasterConfiguration?
    private let runner: any CommandRunning

    public init(
        connectTimeout: Int = 5,
        strictHostKeyChecking: String = "accept-new",
        controlMaster: SSHControlMasterConfiguration? = SSHControlMasterConfiguration(),
        runner: any CommandRunning = ProcessCommandRunner()
    ) {
        self.connectTimeout = connectTimeout
        self.strictHostKeyChecking = strictHostKeyChecking
        self.controlMaster = controlMaster
        self.runner = runner
    }

    /// `[user@]host:port` 에 접속해 `command` 를 실행. 성공 시 stdout, 실패 시 분류된 에러.
    public func run(host: String, user: String, port: Int, command: String) async -> Result<String, SSHExecError> {
        await run(host: host, user: user, port: port, command: command, timeout: nil)
    }

    /// 전체 프로세스 제한 시간을 적용해 원격 명령을 실행한다.
    public func run(
        host: String,
        user: String,
        port: Int,
        command: String,
        timeout: TimeInterval?
    ) async -> Result<String, SSHExecError> {
        let controlSocket: URL?
        if let controlMaster {
            do {
                try controlMaster.prepareControlDirectory()
            } catch {
                return .failure(.commandFailed("cannot prepare SSH control directory: \(error.localizedDescription)"))
            }
            controlSocket = controlMaster.controlSocketURL(user: user, host: host, port: port)
        } else {
            controlSocket = nil
        }

        var arguments = [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=\(connectTimeout)",
            "-o", "StrictHostKeyChecking=\(strictHostKeyChecking)",
        ]
        if let controlMaster, let controlSocket {
            arguments += controlMaster.options(controlSocket: controlSocket)
        }
        arguments += [
            "-p", String(port),
            "\(user)@\(host)",
            command,
        ]
        var result = await runner.run("/usr/bin/ssh", arguments, timeout: timeout)
        if let controlSocket,
           SSHControlMasterConfiguration.isStaleControlSocketError(result.stderr) {
            try? FileManager.default.removeItem(at: controlSocket)
            result = await runner.run("/usr/bin/ssh", arguments, timeout: timeout)
        }
        if result.exitCode == 0 {
            return .success(result.stdout)
        }
        let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if SSHAuth.isAuthFailure(result.stderr) {
            return .failure(.authFailure(stderr))
        }
        return .failure(.unreachable(stderr))
    }
}
