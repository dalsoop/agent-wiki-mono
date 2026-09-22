import Foundation

/// Single entry/exit for coding-agent home attach, emit checks, and skill-root scan.
///
/// Do not join `~/.claude/skills` in callers. Seeds, coverage, and scan roots
/// all come from `AgentCLILayout.managed`.
public enum AgentSurfaceGate {
    public struct Seeds: Sendable, Equatable {
        public var catalogSeedRoot: URL?
        public var skillRoots: [URL]
        public var agentRoots: [URL]

        public init(catalogSeedRoot: URL? = nil, skillRoots: [URL] = [], agentRoots: [URL] = []) {
            self.catalogSeedRoot = catalogSeedRoot
            self.skillRoots = skillRoots
            self.agentRoots = agentRoots
        }

        /// App + repo seed dirs derived from the claude-shaped repo layout.
        public static func forApp(appDir: URL, repoRoot: URL) -> Seeds {
            let seed = AgentCLILayout.claude
            let appHome = appDir.appendingPathComponent(seed.home.rootRelative, isDirectory: true)
            let repoHome = repoRoot.appendingPathComponent(seed.home.rootRelative, isDirectory: true)
            return Seeds(
                catalogSeedRoot: repoRoot.appendingPathComponent(".kiro/skills", isDirectory: true),
                skillRoots: [
                    appDir.appendingPathComponent("Packaging/Skills", isDirectory: true),
                    appDir.appendingPathComponent(".kiro/skills", isDirectory: true),
                    appHome.appendingPathComponent(seed.home.skillsSubpath, isDirectory: true),
                ],
                agentRoots: [
                    appHome.appendingPathComponent("agents", isDirectory: true),
                    repoHome.appendingPathComponent("agents", isDirectory: true),
                ]
            )
        }
    }

    public struct ScanRoot: Sendable, Equatable {
        public var hostId: String
        public var path: String
        public var via: String
    }

    public struct Coverage: Sendable, Equatable {
        public var missingSkills: [String]
        public var missingAgents: [String]
        public var needsEmit: Bool { !missingSkills.isEmpty || !missingAgents.isEmpty }
    }

    public static func attach(
        profile: AgentSurfaceProfile,
        seeds: Seeds,
        seedBundle: Bundle = .main,
        catalogRoots: [URL]? = nil,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) throws -> AgentSurfaceRules.AttachResult {
        try AgentSurfaceRules.performAttach(
            profile: profile,
            seedBundle: seedBundle,
            seedRoot: seeds.catalogSeedRoot,
            seedRoots: seeds.skillRoots,
            agentRoots: seeds.agentRoots,
            catalogRoots: catalogRoots,
            home: home
        )
    }

    public static func detach(
        profile: AgentSurfaceProfile,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) throws -> AgentSurfaceRules.AttachResult {
        try AgentSurfaceRules.detach(profile: profile, home: home)
    }

    public static func status(
        profile: AgentSurfaceProfile,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> AgentSurfaceRules.Status {
        AgentSurfaceRules.status(profile: profile, home: home)
    }

    public static func coverage(
        skills: [String],
        agents: [String],
        userHome: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> Coverage {
        let layouts = AgentCLILayout.managed
        let missingSkills = skills.filter { name in
            !layouts.contains { $0.hasSkill(name, userHome: userHome) }
        }
        let missingAgents = agents.filter { name in
            !layouts.contains { $0.hasAgent(name, userHome: userHome) }
        }
        return Coverage(missingSkills: missingSkills, missingAgents: missingAgents)
    }

    public static func needsEmit(
        skills: [String],
        agents: [String],
        userHome: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> Bool {
        coverage(skills: skills, agents: agents, userHome: userHome).needsEmit
    }

    /// Home (and optional project) skill/agent dirs for every managed CLI.
    public static func scanRoots(
        userHome: URL,
        workspace: URL? = nil
    ) -> [ScanRoot] {
        var out: [ScanRoot] = []
        for layout in AgentCLILayout.managed {
            if layout.attachesSkills {
                out.append(ScanRoot(
                    hostId: layout.id,
                    path: layout.home.skillsURL(home: userHome).path,
                    via: "user skills"
                ))
                if let workspace {
                    out.append(ScanRoot(
                        hostId: layout.id,
                        path: layout.home.skillsURL(home: workspace).path,
                        via: "project skills"
                    ))
                }
            }
            if layout.attachesAgents {
                out.append(ScanRoot(
                    hostId: layout.id,
                    path: layout.home.agentsURL(home: userHome).path,
                    via: "user agents"
                ))
                if let workspace {
                    out.append(ScanRoot(
                        hostId: layout.id,
                        path: layout.home.agentsURL(home: workspace).path,
                        via: "project agents"
                    ))
                }
            }
            for extra in layout.extraSkillSubpaths {
                out.append(ScanRoot(
                    hostId: layout.id,
                    path: layout.home.rootURL(home: userHome).appendingPathComponent(extra).path,
                    via: extra
                ))
            }
        }
        return out
    }

    public static func appSeedFiles(appDir: URL, name: String) -> (agent: URL, skill: URL, appKiro: URL) {
        let seed = AgentCLILayout.claude
        let appHome = appDir.appendingPathComponent(seed.home.rootRelative, isDirectory: true)
        return (
            appHome.appendingPathComponent("agents/\(name).md"),
            appHome.appendingPathComponent("\(seed.home.skillsSubpath)/\(name)/SKILL.md"),
            appDir.appendingPathComponent(".kiro/skills/\(name)/SKILL.md")
        )
    }

    public static func appAgentsDirectory(appDir: URL) -> URL {
        let seed = AgentCLILayout.claude
        return appDir
            .appendingPathComponent(seed.home.rootRelative, isDirectory: true)
            .appendingPathComponent("agents", isDirectory: true)
    }

    /// First managed home that already has this skill — for records publish.
    public static func publishedSkillDirectory(
        name: String,
        userHome: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL? {
        AgentCLILayout.managed.first { $0.hasSkill(name, userHome: userHome) }
            .map { $0.skillFile(name: name, userHome: userHome).deletingLastPathComponent() }
    }
}
