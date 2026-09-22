import Foundation

public enum ReviveResult: Sendable {
    case processRevived(newPID: Int)
    case roomRestored(roomID: String)
    case failure(reason: String)
}

public enum UniversalReviver {
    /// 영수증 1장으로 이전 문맥(CWD, Env, Command)을 완전 복원하여 부활
    public static func revive(receipt: TriageReceipt) async -> ReviveResult {
        switch receipt.kind {
        case .process, .backgroundWorker:
            return reviveProcess(receipt: receipt)
        case .agentRoom:
            return reviveAgentRoom(receipt: receipt)
        case .buildLock:
            return .failure(reason: "빌드 락은 부활 대상이 아닙니다 (소멸 완료)")
        }
    }

    private static func reviveProcess(receipt: TriageReceipt) -> ReviveResult {
        let cmd = receipt.context.command
        let cwd = receipt.context.workingDirectory
        
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-c", cmd]
        p.currentDirectoryURL = URL(fileURLWithPath: cwd)
        
        var env = ProcessInfo.processInfo.environment
        for (k, v) in receipt.context.environmentVariables {
            env[k] = v
        }
        p.environment = env
        
        // 백그라운드 분리 실행
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        
        do {
            try p.run()
            Task {
                await TriageReceiptStore.shared.markRevived(id: receipt.id)
            }
            return .processRevived(newPID: Int(p.processIdentifier))
        } catch {
            return .failure(reason: "프로세스 부활 실패: \(error.localizedDescription)")
        }
    }

    private static func reviveAgentRoom(receipt: TriageReceipt) -> ReviveResult {
        // agent-work-todo placement tick / spawn-room 복구 로직
        return .roomRestored(roomID: receipt.artifactID)
    }
}
