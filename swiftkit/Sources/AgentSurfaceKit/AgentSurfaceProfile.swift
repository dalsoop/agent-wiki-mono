import Foundation
import StateRootKit

/// Coding-agent home that can host skills (and later agent defs).
public struct AgentHome: Sendable, Equatable, Hashable {
    public var id: String
    /// Root for that agent, e.g. `~/.codex`
    public var rootRelative: String
    /// Skills directory under root, usually `skills`
    public var skillsSubpath: String

    public init(id: String, rootRelative: String, skillsSubpath: String = "skills") {
        self.id = id
        self.rootRelative = rootRelative
        self.skillsSubpath = skillsSubpath
    }

    public func rootURL(home: URL = StateRootKit.url(for: "")) -> URL {
        if rootRelative.hasPrefix("/") {
            return URL(fileURLWithPath: rootRelative)
        }
        return home.appendingPathComponent(rootRelative, isDirectory: true)
    }

    public func skillsURL(home: URL = StateRootKit.url(for: "")) -> URL {
        rootURL(home: home).appendingPathComponent(skillsSubpath, isDirectory: true)
    }

    /// Agent definition files, e.g. `~/.claude/agents/<name>.md`.
    public func agentsURL(home: URL = StateRootKit.url(for: "")) -> URL {
        rootURL(home: home).appendingPathComponent("agents", isDirectory: true)
    }

    public func isPresent(home: URL = StateRootKit.url(for: "")) -> Bool {
        FileManager.default.fileExists(atPath: rootURL(home: home).path)
    }

    public static let codex = AgentHome(id: "codex", rootRelative: ".codex")
    public static let claude = AgentHome(id: "claude", rootRelative: ".claude")
    public static let grok = AgentHome(id: "grok", rootRelative: ".grok")
    public static let cursor = AgentHome(id: "cursor", rootRelative: ".cursor")
    public static let agents = AgentHome(id: "agents", rootRelative: ".agents")

    /// Default homes — same ids as `AgentCLILayout.managed`.
    public static let defaults: [AgentHome] = AgentCLILayout.managed.map(\.home)
}

/// What an app attaches for coding agents when installed.
public struct AgentSurfaceProfile: Sendable, Equatable {
    /// Owner CLI / app id (e.g. `agent-wiki`). Manifest key.
    public var ownerCLI: String
    /// Skill directory names to attach.
    public var skills: [String]
    /// Agent definition basenames (`<name>.md` under each home `agents/`).
    public var agents: [String]
    /// Homes to consider (only present ones are used).
    public var homes: [AgentHome]
    /// Prefer symlink to catalog when found; else copy seed.
    public var preferCatalogSymlink: Bool

    public init(
        ownerCLI: String,
        skills: [String],
        agents: [String] = [],
        homes: [AgentHome] = AgentHome.defaults,
        preferCatalogSymlink: Bool = true
    ) {
        self.ownerCLI = ownerCLI
        self.skills = skills
        self.agents = agents
        self.homes = homes
        self.preferCatalogSymlink = preferCatalogSymlink
    }

    /// Load from package-identity.json `agent_surface` object (or top-level skills).
    public static func load(fromPackageIdentity url: URL) -> AgentSurfaceProfile? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            return load(fromIdentityObject: obj)
        } catch {
            return nil
        }
    }

    public static func load(fromIdentityObject obj: [String: Any]) -> AgentSurfaceProfile? {
        let cli = (obj["cli_product"] as? String)
            ?? (obj["cli"] as? String)
            ?? (obj["program"] as? String)
            ?? ""
        guard !cli.isEmpty else { return nil }
        let surface = obj["agent_surface"] as? [String: Any] ?? [:]
        let skills = (surface["skills"] as? [String])
            ?? (obj["skills"] as? [String])
            ?? [cli]
        let agents = (surface["agents"] as? [String]) ?? []
        let prefer = (surface["prefer_catalog_symlink"] as? Bool) ?? true
        return AgentSurfaceProfile(
            ownerCLI: cli,
            skills: skills,
            agents: agents,
            preferCatalogSymlink: prefer
        )
    }
}

/// One installed skill link/copy record.
public struct AttachedSkillRecord: Codable, Sendable, Equatable {
    public var skill: String
    public var homeId: String
    public var path: String
    public var mode: String // "symlink" | "copy"
    public var source: String?

    public init(skill: String, homeId: String, path: String, mode: String, source: String? = nil) {
        self.skill = skill
        self.homeId = homeId
        self.path = path
        self.mode = mode
        self.source = source
    }
}

/// Manifest of what this app attached — used for safe detach.
public struct AgentSurfaceManifest: Codable, Sendable, Equatable {
    public var ownerCLI: String
    public var updatedAt: String
    public var skills: [AttachedSkillRecord]
    public var agents: [AttachedSkillRecord]

    public init(
        ownerCLI: String,
        updatedAt: String = ISO8601DateFormatter().string(from: Date()),
        skills: [AttachedSkillRecord] = [],
        agents: [AttachedSkillRecord] = []
    ) {
        self.ownerCLI = ownerCLI
        self.updatedAt = updatedAt
        self.skills = skills
        self.agents = agents
    }
}
