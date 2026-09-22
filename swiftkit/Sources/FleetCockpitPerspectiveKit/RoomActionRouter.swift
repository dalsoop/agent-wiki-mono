import Foundation
import CommandKit

/// 1-Click 네이티브 점프 및 터미널 라우팅 중앙 정본
public enum RoomActionRouter: Sendable {
    public static let agentDeckBundleID = "net.ranode.agentdeck"
    public static let agentDeckAppPath = "/Applications/AgentDeck.app"

    /// 지정된 경로로 터미널/에이전트덱 작업공간을 활성화 (환경변수는 전역 setenv 오염 없이 서브프로세스에 핀포인트 격리 주입)
    @discardableResult
    public static func openRoom(
        path: String,
        environment: [String: String] = [:],
        runner: CommandRunning = ProcessCommandRunner(),
        fileManager: FileManager = .default
    ) async -> CommandResult {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            return CommandResult(stdout: "", stderr: "Empty path", exitCode: 1)
        }

        var envArgs: [String] = []
        for (k, v) in environment.sorted(by: { $0.key < $1.key }) {
            envArgs += ["--env", "\(k)=\(v)"]
        }

        if fileManager.fileExists(atPath: agentDeckAppPath) {
            let res = await runner.run("/usr/bin/open", ["-n"] + envArgs + ["-b", agentDeckBundleID, "--args", trimmedPath], timeout: 4)
            if res.ok { return res }
        }

        // 폴백: 시스템 Terminal.app (-n 플래그로 새 인스턴스를 강제하여 이미 켜진 Terminal.app의 --env 무시 방지)
        return await runner.run("/usr/bin/open", ["-n"] + envArgs + ["-a", "Terminal", trimmedPath], timeout: 4)
    }

    /// 동기 실행 래퍼 (기존 RoomSource 호환)
    public static func openRoomSync(path: String, environment: [String: String] = [:]) {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return }

        Task.detached(priority: .userInitiated) {
            _ = await openRoom(path: trimmedPath, environment: environment, fileManager: .default)
        }
    }
}
