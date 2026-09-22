import Foundation
import StateRootKit

/// Attach / detach coding-agent skills for an app surface.
///
/// - **SSOT for skill text**: host-skills-mono catalog when present.
/// - **Seed fallback**: app-bundled `plugin/<skill>/SKILL.md` (or directory).
/// - **Runtime**: `~/.codex|claude|grok|agents/skills/<name>` (symlink preferred).
/// - **Detach**: only removes paths recorded in `~/.agent-surface/<owner>.json`
///   that this owner attached — does not prune host-skills deploy entries blindly.
public enum AgentSurfaceRules {
    public static let manifestDirName = ".agent-surface"

    public struct AttachResult: Sendable, Equatable {
        public var attached: [AttachedSkillRecord]
        public var skipped: [String]
        public var errors: [String]
        public var ok: Bool { errors.isEmpty && !attached.isEmpty || (errors.isEmpty && skipped.isEmpty == false && attached.isEmpty == false) || (errors.isEmpty && !attached.isEmpty) }

        public init(attached: [AttachedSkillRecord] = [], skipped: [String] = [], errors: [String] = []) {
            self.attached = attached
            self.skipped = skipped
            self.errors = errors
        }
    }

    public struct Status: Sendable, Equatable {
        public var presentHomes: [String]
        public var installed: [AttachedSkillRecord]
        public var missing: [String]
        public var manifest: AgentSurfaceManifest?

        public init(
            presentHomes: [String] = [],
            installed: [AttachedSkillRecord] = [],
            missing: [String] = [],
            manifest: AgentSurfaceManifest? = nil
        ) {
            self.presentHomes = presentHomes
            self.installed = installed
            self.missing = missing
            self.manifest = manifest
        }
    }

    // MARK: - Paths

    public static func manifestURL(
        ownerCLI: String,
        home: URL = StateRootKit.url(for: "")
    ) -> URL {
        home.appendingPathComponent(manifestDirName, isDirectory: true)
            .appendingPathComponent("\(ownerCLI).json")
    }

    /// Candidate roots for host-skills-mono catalog (`skills/` parent).
    public static func defaultCatalogRoots(
        home: URL = StateRootKit.url(for: "")
    ) -> [URL] {
        let env = ProcessInfo.processInfo.environment["HOST_SKILLS_ROOT"]
        var roots: [URL] = []
        if let env, !env.isEmpty {
            roots.append(URL(fileURLWithPath: (env as NSString).expandingTildeInPath))
        }
        let candidates = [
            "Documents/WORK/WORKSPACE/ai-tools/host-skills-mono/main",
            "Documents/WORK/WORKSPACE/ai-tools/host-skills-mono",
            // agent-approval 등 personal-mac skills (root-agent-md-mono)
            "Documents/WORK/WORKSPACE/ai-tools/root-agent-md-mono/main/personal-mac",
            "Documents/WORK/WORKSPACE/ai-tools/root-agent-md-mono/main",
        ]
        for rel in candidates {
            roots.append(home.appendingPathComponent(rel, isDirectory: true))
        }
        if let extra = ProcessInfo.processInfo.environment["AGENT_SKILLS_CATALOG_ROOTS"] {
            for part in extra.split(separator: ":") {
                let s = String(part).trimmingCharacters(in: .whitespaces)
                if !s.isEmpty {
                    roots.append(URL(fileURLWithPath: (s as NSString).expandingTildeInPath))
                }
            }
        }
        return roots
    }

    /// Find catalog skill directory: `skills/(category)/<name>` or `skills/<name>`.
    public static func resolveCatalogSkill(
        name: String,
        catalogRoots: [URL]? = nil,
        home: URL = StateRootKit.url(for: "")
    ) -> URL? {
        let fm = FileManager.default
        let roots = catalogRoots ?? defaultCatalogRoots(home: home)
        for root in roots {
            let skillsRoot = root.appendingPathComponent("skills", isDirectory: true)
            guard fm.fileExists(atPath: skillsRoot.path) else { continue }
            // Direct
            let direct = skillsRoot.appendingPathComponent(name, isDirectory: true)
            if fm.fileExists(atPath: direct.appendingPathComponent("SKILL.md").path) {
                return direct
            }
            // Category folders: skills/(knowledge)/name
            let entries: [URL]
            do {
                entries = try fm.contentsOfDirectory(
                    at: skillsRoot, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
                )
            } catch {
                entries = []
            }
            for entry in entries {
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: entry.path, isDirectory: &isDir), isDir.boolValue else { continue }
                let candidate = entry.appendingPathComponent(name, isDirectory: true)
                if fm.fileExists(atPath: candidate.appendingPathComponent("SKILL.md").path) {
                    return candidate
                }
            }
        }
        return nil
    }

    /// Bundled seed: `plugin/<skill>/SKILL.md` or `plugin/<skill>.md` under bundle resources.
    public static func resolveBundledSkill(
        name: String,
        bundle: Bundle,
        seedRoot: URL? = nil,
        seedRoots: [URL] = []
    ) -> URL? {
        let fm = FileManager.default
        var roots: [URL] = []
        // App seeds first; repo/catalog seedRoot is fallback only.
        for seed in (seedRoots + [seedRoot].compactMap { $0 }) {
            roots.append(seed)
            roots.append(seed.appendingPathComponent("plugin", isDirectory: true))
        }
        if let res = bundle.resourceURL {
            roots.append(res)
            roots.append(res.appendingPathComponent("plugin", isDirectory: true))
            // macOS .app: SPM resource bundles live under Contents/Resources/*.bundle
            // (not next to MacOS executable). Scan nested bundles so GUI attach finds
            // plugin/<skill>/SKILL.md without relying on host-skills catalog.
            let resEntries: [URL]
            do {
                resEntries = try fm.contentsOfDirectory(at: res, includingPropertiesForKeys: nil)
            } catch {
                resEntries = []
            }
            for b in resEntries where b.pathExtension == "bundle" {
                roots.append(b)
                roots.append(b.appendingPathComponent("plugin", isDirectory: true))
            }
        }
        // SPM resource bundle next to executable (CLI / Helpers install layout)
        if let exe = bundle.executableURL?.deletingLastPathComponent() {
            let exeEntries: [URL]
            do {
                exeEntries = try fm.contentsOfDirectory(at: exe, includingPropertiesForKeys: nil)
            } catch {
                exeEntries = []
            }
            for b in exeEntries where b.pathExtension == "bundle" {
                roots.append(b)
                roots.append(b.appendingPathComponent("plugin", isDirectory: true))
            }
        }
        for root in roots {
            let dir = root.appendingPathComponent(name, isDirectory: true)
            let skillMD = dir.appendingPathComponent("SKILL.md")
            if fm.fileExists(atPath: skillMD.path) { return dir }
            let flat = root.appendingPathComponent("\(name)/SKILL.md")
            if fm.fileExists(atPath: flat.path) {
                return flat.deletingLastPathComponent()
            }
            if let url = bundle.url(forResource: "SKILL", withExtension: "md", subdirectory: "plugin/\(name)") {
                return url.deletingLastPathComponent()
            }
        }
        return nil
    }

    /// `agents/<name>.md` or `<name>.md` under seed roots.
    public static func resolveAgentDefinition(name: String, seedRoots: [URL]) -> URL? {
        let fm = FileManager.default
        for root in seedRoots {
            let nested = root.appendingPathComponent("\(name).md")
            if fm.fileExists(atPath: nested.path) { return nested }
            let dir = root.appendingPathComponent(name, isDirectory: true)
                .appendingPathComponent("AGENT.md")
            if fm.fileExists(atPath: dir.path) { return dir }
        }
        return nil
    }

    // MARK: - Status

    public static func status(
        profile: AgentSurfaceProfile,
        home: URL = StateRootKit.url(for: "")
    ) -> Status {
        let fm = FileManager.default
        let present = profile.homes.filter { $0.isPresent(home: home) }
        var installed: [AttachedSkillRecord] = []
        var missing: [String] = []
        for skill in profile.skills {
            var any = false
            for h in present where AgentCLILayout.forHome(h).attachesSkills {
                let skillFile = AgentCLILayout.forHome(h).skillFile(name: skill, userHome: home)
                let dest = skillFile.deletingLastPathComponent()
                if fm.fileExists(atPath: skillFile.path) {
                    let mode: String
                    let isSymlink: Bool
                    do {
                        _ = try fm.destinationOfSymbolicLink(atPath: dest.path)
                        isSymlink = true
                    } catch {
                        isSymlink = false
                    }
                    if isSymlink {
                        mode = "symlink"
                    } else {
                        mode = "copy"
                    }
                    installed.append(AttachedSkillRecord(
                        skill: skill, homeId: h.id, path: dest.path, mode: mode))
                    any = true
                }
            }
            if !any { missing.append(skill) }
        }
        for agent in profile.agents {
            var any = false
            for h in present where AgentCLILayout.forHome(h).attachesAgents {
                let dest = AgentCLILayout.forHome(h).agentFile(name: agent, userHome: home)
                if fm.fileExists(atPath: dest.path) {
                    any = true
                }
            }
            if !any { missing.append("agent:\(agent)") }
        }
        let manifest = readManifest(ownerCLI: profile.ownerCLI, home: home)
        return Status(
            presentHomes: present.map(\.id),
            installed: installed,
            missing: missing,
            manifest: manifest
        )
    }

    // MARK: - Attach

    /// Compatibility wrapper that only forwards to `AgentSurfaceGate.attach`.
    /// Do not add new call sites. Migrate wiki/browser in their own MRs.
    public static func attach(
        profile: AgentSurfaceProfile,
        seedBundle: Bundle = .main,
        seedRoot: URL? = nil,
        seedRoots: [URL] = [],
        agentRoots: [URL] = [],
        catalogRoots: [URL]? = nil,
        home: URL = StateRootKit.url(for: "")
    ) throws -> AttachResult {
        try AgentSurfaceGate.attach(
            profile: profile,
            seeds: .init(catalogSeedRoot: seedRoot, skillRoots: seedRoots, agentRoots: agentRoots),
            seedBundle: seedBundle,
            catalogRoots: catalogRoots,
            home: home
        )
    }

    /// Implementation. Only `AgentSurfaceGate` should call this.
    static func performAttach(
        profile: AgentSurfaceProfile,
        seedBundle: Bundle,
        seedRoot: URL?,
        seedRoots: [URL],
        agentRoots: [URL],
        catalogRoots: [URL]?,
        home: URL
    ) throws -> AttachResult {
        let fm = FileManager.default
        let present = profile.homes.filter { $0.isPresent(home: home) }
        var attached: [AttachedSkillRecord] = []
        var skipped: [String] = []
        var errors: [String] = []

        if present.isEmpty {
            return AttachResult(skipped: ["no agent homes present (~/.codex|claude|grok|agents)"])
        }

        var agentAttached: [AttachedSkillRecord] = []

        for skill in profile.skills {
            let catalog = resolveCatalogSkill(name: skill, catalogRoots: catalogRoots, home: home)
            let bundled = resolveBundledSkill(
                name: skill, bundle: seedBundle, seedRoot: seedRoot, seedRoots: seedRoots
            )
            let sourceURL: URL?
            let modePreferred: String
            if profile.preferCatalogSymlink, let catalog {
                sourceURL = catalog
                modePreferred = "symlink"
            } else if let bundled {
                sourceURL = bundled
                modePreferred = "copy"
            } else if let catalog {
                sourceURL = catalog
                modePreferred = "symlink"
            } else {
                errors.append("skill '\(skill)': no catalog or bundled seed")
                continue
            }
            guard let sourceURL else { continue }
            let skillMD = sourceURL.appendingPathComponent("SKILL.md")
            guard fm.fileExists(atPath: skillMD.path) else {
                errors.append("skill '\(skill)': missing SKILL.md at \(sourceURL.path)")
                continue
            }

            for h in present where AgentCLILayout.forHome(h).attachesSkills {
                let layout = AgentCLILayout.forHome(h)
                let skillFile = layout.skillFile(name: skill, userHome: home)
                let dest = skillFile.deletingLastPathComponent()
                do {
                    try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                    if fm.fileExists(atPath: skillFile.path) {
                        let isLink = (try? fm.destinationOfSymbolicLink(atPath: dest.path)) != nil
                            || (try? fm.destinationOfSymbolicLink(atPath: skillFile.path)) != nil
                        if isLink || bundled == nil {
                            attached.append(AttachedSkillRecord(
                                skill: skill, homeId: h.id, path: dest.path,
                                mode: "preexisting", source: sourceURL.path))
                            continue
                        }
                        // Leftover directory copy — refresh from this owner's seed.
                        try fm.removeItem(at: dest)
                    }
                    if modePreferred == "symlink" {
                        try fm.createSymbolicLink(at: dest, withDestinationURL: sourceURL)
                        attached.append(AttachedSkillRecord(
                            skill: skill, homeId: h.id, path: dest.path,
                            mode: "symlink", source: sourceURL.path))
                    } else {
                        try fm.copyItem(at: sourceURL, to: dest)
                        attached.append(AttachedSkillRecord(
                            skill: skill, homeId: h.id, path: dest.path,
                            mode: "copy", source: sourceURL.path))
                    }
                } catch {
                    errors.append("\(h.id)/\(skill): \(error.localizedDescription)")
                }
            }
        }

        for agent in profile.agents {
            guard let source = resolveAgentDefinition(name: agent, seedRoots: agentRoots) else {
                errors.append("agent '\(agent)': no definition seed")
                continue
            }
            for h in present where AgentCLILayout.forHome(h).attachesAgents {
                let dest = AgentCLILayout.forHome(h).agentFile(name: agent, userHome: home)
                do {
                    try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                    if fm.fileExists(atPath: dest.path) {
                        let isLink = (try? fm.destinationOfSymbolicLink(atPath: dest.path)) != nil
                        if isLink {
                            agentAttached.append(AttachedSkillRecord(
                                skill: agent, homeId: h.id, path: dest.path,
                                mode: "preexisting", source: source.path))
                            continue
                        }
                        try fm.removeItem(at: dest)
                    }
                    try fm.copyItem(at: source, to: dest)
                    agentAttached.append(AttachedSkillRecord(
                        skill: agent, homeId: h.id, path: dest.path,
                        mode: "copy", source: source.path))
                } catch {
                    errors.append("\(h.id)/agent/\(agent): \(error.localizedDescription)")
                }
            }
        }

        let manifest = AgentSurfaceManifest(
            ownerCLI: profile.ownerCLI,
            skills: attached,
            agents: agentAttached
        )
        attached.append(contentsOf: agentAttached)
        try writeManifest(manifest, home: home)

        if attached.isEmpty && errors.isEmpty {
            skipped.append("nothing attached")
        }
        return AttachResult(attached: attached, skipped: skipped, errors: errors)
    }

    // MARK: - Detach

    /// Remove only attachments recorded for this owner.
    public static func detach(
        profile: AgentSurfaceProfile,
        home: URL = StateRootKit.url(for: "")
    ) throws -> AttachResult {
        let fm = FileManager.default
        guard let manifest = readManifest(ownerCLI: profile.ownerCLI, home: home) else {
            return AttachResult(skipped: ["no manifest for \(profile.ownerCLI)"])
        }
        var removed: [AttachedSkillRecord] = []
        var errors: [String] = []
        for rec in manifest.skills + manifest.agents {
            // host-skills / 사용자가 이미 둔 것은 건드리지 않음
            if rec.mode == "preexisting" { continue }
            let url = URL(fileURLWithPath: rec.path)
            guard fm.fileExists(atPath: url.path) else { continue }
            let isSkill = rec.path.contains("/skills/\(rec.skill)")
                || rec.path.hasSuffix("/skills/\(rec.skill)")
                || url.lastPathComponent == rec.skill
            let isAgent = rec.path.contains("/agents/\(rec.skill).md")
                || url.lastPathComponent == "\(rec.skill).md"
            guard isSkill || isAgent else {
                errors.append("refuse detach odd path: \(rec.path)")
                continue
            }
            do {
                try fm.removeItem(at: url)
                removed.append(rec)
            } catch {
                errors.append("\(rec.path): \(error.localizedDescription)")
            }
        }
        // Clear or rewrite empty manifest
        let empty = AgentSurfaceManifest(ownerCLI: profile.ownerCLI, skills: [], agents: [])
        try writeManifest(empty, home: home)
        return AttachResult(attached: removed, errors: errors)
    }

    // MARK: - Manifest IO

    public static func readManifest(
        ownerCLI: String,
        home: URL = StateRootKit.url(for: "")
    ) -> AgentSurfaceManifest? {
        let url = manifestURL(ownerCLI: ownerCLI, home: home)
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder().decode(AgentSurfaceManifest.self, from: data)
        } catch {
            return nil
        }
    }

    public static func writeManifest(
        _ manifest: AgentSurfaceManifest,
        home: URL = StateRootKit.url(for: "")
    ) throws {
        let url = manifestURL(ownerCLI: manifest.ownerCLI, home: home)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(manifest).write(to: url, options: .atomic)
    }
}
