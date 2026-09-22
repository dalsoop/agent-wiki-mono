import Foundation
import InteropKit

/// One coding-agent CLI's **home layout** — what emit/status may attach.
///
/// Argv/실행은 `CodingAgentBridgeKit` 가 같은 id(`claude`/`codex`/`grok`)로 맡는다.
/// 여기 표가 없으면 홈 경로를 호출마다 하드코딩하게 된다.
public struct AgentCLILayout: Sendable, Equatable, Hashable, Identifiable {
    public var home: AgentHome
    public var cliNames: [String]
    public var cliEnv: String?
    public var attachesSkills: Bool
    public var attachesAgents: Bool
    /// Extra skill dirs under the home root, e.g. grok `bundled/skills`.
    public var extraSkillSubpaths: [String]

    public var id: String { home.id }

    public init(
        home: AgentHome,
        cliNames: [String],
        cliEnv: String? = nil,
        attachesSkills: Bool = true,
        attachesAgents: Bool = false,
        extraSkillSubpaths: [String] = []
    ) {
        self.home = home
        self.cliNames = cliNames
        self.cliEnv = cliEnv
        self.attachesSkills = attachesSkills
        self.attachesAgents = attachesAgents
        self.extraSkillSubpaths = extraSkillSubpaths
    }

    public static let claude = AgentCLILayout(
        home: .claude,
        cliNames: ["claude"],
        cliEnv: "CLAUDE_CLI",
        attachesSkills: true,
        attachesAgents: true
    )
    public static let codex = AgentCLILayout(
        home: .codex,
        cliNames: ["codex"],
        cliEnv: "CODEX_CLI",
        attachesSkills: true,
        attachesAgents: false
    )
    public static let grok = AgentCLILayout(
        home: .grok,
        cliNames: ["grok"],
        cliEnv: "GROK_CLI",
        attachesSkills: true,
        attachesAgents: true,
        extraSkillSubpaths: ["bundled/skills"]
    )
    public static let cursor = AgentCLILayout(
        home: .cursor,
        cliNames: ["cursor", "cursor-agent"],
        cliEnv: "CURSOR_CLI",
        attachesSkills: true,
        attachesAgents: false
    )
    public static let agents = AgentCLILayout(
        home: .agents,
        cliNames: [],
        attachesSkills: true,
        attachesAgents: false
    )

    /// Known CLIs we manage. Unknown test/home ids fall back via `forHome`.
    public static let managed: [AgentCLILayout] = [
        .claude, .codex, .grok, .cursor, .agents,
    ]

    public static func forHome(_ home: AgentHome) -> AgentCLILayout {
        managed.first { $0.home.id == home.id }
            ?? AgentCLILayout(
                home: home,
                cliNames: [home.id],
                attachesSkills: true,
                attachesAgents: true
            )
    }

    public func skillFile(name: String, userHome: URL) -> URL {
        home.skillsURL(home: userHome)
            .appendingPathComponent(name, isDirectory: true)
            .appendingPathComponent("SKILL.md")
    }

    public func agentFile(name: String, userHome: URL) -> URL {
        home.agentsURL(home: userHome).appendingPathComponent("\(name).md")
    }

    public func hasSkill(_ name: String, userHome: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool {
        guard attachesSkills else { return false }
        return FileManager.default.fileExists(atPath: skillFile(name: name, userHome: userHome).path)
    }

    public func hasAgent(_ name: String, userHome: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool {
        guard attachesAgents else { return false }
        return FileManager.default.fileExists(atPath: agentFile(name: name, userHome: userHome).path)
    }

    /// Env override, then brew-style bins. Execution argv is not this type's job.
    public func resolveExecutable() -> String? {
        let fm = FileManager.default
        if let cliEnv, let value = ProcessInfo.processInfo.environment[cliEnv], !value.isEmpty,
           fm.isExecutableFile(atPath: value) {
            return value
        }
        for name in cliNames {
            for root in HostPlatform.standardBinPaths {
                let path = "\(root)/\(name)"
                if fm.isExecutableFile(atPath: path) { return path }
            }
        }
        return nil
    }
}
