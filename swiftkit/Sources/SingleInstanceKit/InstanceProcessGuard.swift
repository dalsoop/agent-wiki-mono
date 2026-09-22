import Foundation

/// SingleInstanceKit의 통합 파사드(Facade).
///
/// GUI 앱과 CLI 도구의 진입점에서 한 줄로 안전하게 호출되어
/// 스코프 해석, 커널 flock 잠금, UDS 소켓 IPC 리스너 및 포커스 핸드오프를 조율한다.
public enum InstanceProcessGuard {
    public enum GuardResult: Sendable {
        case primary(token: InstanceLockToken, channel: InstanceHandoffChannel?)
        /// 상속 바이패스된 인스턴스 (재귀 호출 등)
        case primaryBypassed(token: InstanceLockToken)
        /// 중복 실행으로 인해 Primary에 포커스를 넘기고 종료 대기
        case secondaryHandedOff(holderPID: pid_t?)
    }

    // MARK: - GUI Application Flow

    /// GUI 앱의 `main.swift` 또는 `App.init` 첫 줄에서 호출하는 표준 가드.
    /// 이미 실행 중인 경우 기존 창을 활성화(IPC 전송)하고 즉시 `exit(0)` 한다.
    @discardableResult
    public static func guardApplication(
        name: String,
        scope: InstanceLockScope = .host,
        exitHandler: ((Int32) -> Void)? = { exit($0) },
        onFocusReceived: (@Sendable (InstanceHandoffChannel.Message) -> Void)? = nil
    ) -> GuardResult {
        let coordinator = InstanceLockCoordinator()
        let result = coordinator.tryAcquire(name: name, scope: scope)

        switch result {
        case .acquired(let token):
            let socketURL = scope.socketURL(name: name)
            let channel = InstanceHandoffChannel(socketURL: socketURL)
            _ = channel.startListening { message in
                onFocusReceived?(message)
            }
            return .primary(token: token, channel: channel)

        case .bypassed(let token):
            return .primaryBypassed(token: token)

        case .busy(let holderPID):
            // Secondary 프로세스: Primary에게 UDS Focus 메시지 전송 시도
            let socketURL = scope.socketURL(name: name)
            _ = InstanceHandoffChannel.sendHandoff(to: socketURL)
            if let exitHandler {
                exitHandler(0)
            }
            return .secondaryHandedOff(holderPID: holderPID)
        }
    }

    // MARK: - CLI Tool Flow

    /// CLI 도구의 진입점에서 호출하여 중복 실행을 차단하는 가드.
    @discardableResult
    public static func exitIfAlreadyRunning(
        name: String,
        scope: InstanceLockScope = .host,
        message: String? = nil,
        exitCode: Int32 = 0,
        stderrWriter: (String) -> Void = { msg in FileHandle.standardError.write(Data((msg + "\n").utf8)) },
        exitHandler: (Int32) -> Void = { code in exit(code) }
    ) -> InstanceLockToken? {
        let coordinator = InstanceLockCoordinator()
        let result = coordinator.tryAcquire(name: name, scope: scope)

        switch result {
        case .acquired(let token), .bypassed(let token):
            return token
        case .busy(let holderPID):
            let desc = holderPID.map { " (held by PID \($0))" } ?? ""
            let finalMsg = message ?? "[\(name)] Another instance is already running\(desc). Exiting."
            stderrWriter(finalMsg)
            exitHandler(exitCode)
            return nil
        }
    }
}
