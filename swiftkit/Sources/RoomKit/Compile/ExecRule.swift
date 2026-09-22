import Foundation

/// 명령 실행 판정 결과
public enum ExecDecision: Equatable, Sendable {
    case allow
    case deny(reason: String)
    case quarantine(reason: String)
}

/// 데몬 exec 및 명령 실행 순수 규칙 판정기 (L3)
///
/// 제한 셸 환경에서의 절대경로/상대경로 실행 방지, 셸 우회 방지,
/// 파괴적 명령 격리(quarantine)를 판정한다.
public enum ExecRule {
    public static let shellBypass: Set<String> = ["sh", "bash", "zsh", "dash", "env"]

    /// 주어진 argv 와 walls 스펙을 기반으로 실행을 허용/거부/격리할지 결정한다.
    public static func decide(argv: [String], walls: RoomWalls) -> ExecDecision {
        guard let first = argv.first, !first.isEmpty else {
            return .allow
        }

        // 1. 파괴적 명령은 프리셋과 무관하게 항상 격리(quarantine)
        if let qReason = quarantineReason(argv: argv) {
            return .quarantine(reason: qReason)
        }

        // 2. 제한 셸(restricted)인 경우 경로 실행 및 셸 우회 차단
        if walls.shell == .restricted {
            if first.contains("/") {
                return .deny(reason: "restricted room: path execution is not allowed (\(first))")
            }
            if shellBypass.contains(first) {
                return .deny(reason: "restricted room: shell bypass is not allowed (\(first))")
            }
        }

        // 3. executables 가 allowList 인 경우 허용 목록 검사
        if case .allowList(let toolbelt) = walls.executables {
            let cmd = commandName(argv)
            if !isExecutableAllowed(command: cmd, raw: first, toolbelt: toolbelt) {
                return .deny(reason: "command not in toolbelt: \(cmd)")
            }
        }

        return .allow
    }

    public static func isExecutableAllowed(command: String, raw: String, toolbelt: [String]) -> Bool {
        if toolbelt.contains(command) || toolbelt.contains(raw) {
            return true
        }
        if PathPlanner.standardPosixNames.contains(command) {
            return true
        }
        if command == "agent-room-terminal" {
            return true
        }
        for tool in toolbelt {
            if let helpers = PathPlanner.agentHelpers[tool], helpers.contains(command) {
                return true
            }
        }
        return false
    }

    public static func commandName(_ argv: [String]) -> String {
        guard let first = argv.first else { return "" }
        return URL(fileURLWithPath: first).lastPathComponent
    }

    public static func quarantineReason(argv: [String]) -> String? {
        let name = commandName(argv)
        if name == "rm", hasShortFlags(argv, "r", "f") {
            return "destructive command is quarantined (rm -rf)"
        }
        if name == "git", argv.contains("push"), hasGitForce(argv) {
            return "destructive command is quarantined (git push --force)"
        }
        if name == "kubectl", argv.contains("delete") {
            return "destructive command is quarantined (kubectl delete)"
        }
        return nil
    }

    private static func hasShortFlags(_ argv: [String], _ flags: Character...) -> Bool {
        flags.allSatisfy { flag in
            argv.dropFirst().contains { token in
                if token == "-\(flag)" { return true }
                if token.hasPrefix("--") { return token == longName(for: flag) }
                return token.hasPrefix("-") && !token.hasPrefix("--") && token.contains(flag)
            }
        }
    }

    private static func longName(for flag: Character) -> String {
        switch flag {
        case "r": return "--recursive"
        case "f": return "--force"
        default: return "--\(flag)"
        }
    }

    private static func hasGitForce(_ argv: [String]) -> Bool {
        argv.contains { token in
            token == "--force" || token == "-f" || token.hasPrefix("--force=")
        }
    }
}
