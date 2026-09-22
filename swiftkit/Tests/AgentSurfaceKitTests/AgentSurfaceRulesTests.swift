import Foundation
import Testing
@testable import AgentSurfaceKit

@Suite struct AgentSurfaceRulesTests {
    @Test func attachSymlinkAndDetach() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("agent-surface-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: root) }

        // Fake home with codex + claude
        let home = root.appendingPathComponent("home", isDirectory: true)
        try fm.createDirectory(at: home.appendingPathComponent(".codex"), withIntermediateDirectories: true)
        try fm.createDirectory(at: home.appendingPathComponent(".claude"), withIntermediateDirectories: true)

        // Catalog skill
        let catalogSkill = root.appendingPathComponent("catalog/skills/(knowledge)/fake-skill", isDirectory: true)
        try fm.createDirectory(at: catalogSkill, withIntermediateDirectories: true)
        try "# Fake\n".write(to: catalogSkill.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let profile = AgentSurfaceProfile(
            ownerCLI: "fake-cli",
            skills: ["fake-skill"],
            homes: [
                AgentHome(id: "codex", rootRelative: home.appendingPathComponent(".codex").path),
                AgentHome(id: "claude", rootRelative: home.appendingPathComponent(".claude").path),
            ]
        )

        let result = try AgentSurfaceRules.attach(
            profile: profile,
            catalogRoots: [root.appendingPathComponent("catalog")],
            home: home
        )
        #expect(result.errors.isEmpty)
        #expect(result.attached.count == 2)

        let st = AgentSurfaceRules.status(profile: profile, home: home)
        #expect(st.missing.isEmpty)
        #expect(st.installed.count == 2)

        // First attach created symlinks (empty homes) — detach removes them
        let det = try AgentSurfaceRules.detach(profile: profile, home: home)
        #expect(det.errors.isEmpty)
        #expect(det.attached.count == 2)
        #expect(AgentSurfaceRules.status(profile: profile, home: home).installed.isEmpty)

        // Re-attach then simulate host-skills (preexisting): second attach must not own detach
        _ = try AgentSurfaceRules.attach(
            profile: profile,
            catalogRoots: [root.appendingPathComponent("catalog")],
            home: home
        )
        // Mark as if we re-ran attach when already present → preexisting not removed
        let mid = try AgentSurfaceRules.attach(
            profile: profile,
            catalogRoots: [root.appendingPathComponent("catalog")],
            home: home
        )
        #expect(mid.attached.allSatisfy { $0.mode == "preexisting" })
        let det2 = try AgentSurfaceRules.detach(profile: profile, home: home)
        #expect(det2.attached.isEmpty) // preexisting skipped
        #expect(!AgentSurfaceRules.status(profile: profile, home: home).installed.isEmpty)
    }

    @Test func loadProfileFromIdentityJSON() throws {
        let json = """
        {
          "cli": "agent-wiki",
          "agent_surface": {
            "skills": ["agent-wiki", "wiki-record"],
            "agents": []
          }
        }
        """.data(using: .utf8)!
        let obj = try JSONSerialization.jsonObject(with: json) as! [String: Any]
        let p = AgentSurfaceProfile.load(fromIdentityObject: obj)
        #expect(p?.ownerCLI == "agent-wiki")
        #expect(p?.skills == ["agent-wiki", "wiki-record"])
    }

    /// host-skills catalog 없이 seedRoot 만으로 multi-home 부착 (클린 머신 GUI attach 경로).
    @Test func attachFromSeedRootWithoutCatalog() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("surface-seed-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: root) }

        let home = root.appendingPathComponent("home", isDirectory: true)
        try fm.createDirectory(at: home.appendingPathComponent(".codex"), withIntermediateDirectories: true)
        try fm.createDirectory(at: home.appendingPathComponent(".claude"), withIntermediateDirectories: true)

        let seed = root.appendingPathComponent("seed/plugin/agent-wiki", isDirectory: true)
        try fm.createDirectory(at: seed, withIntermediateDirectories: true)
        try "# seed only\n".write(to: seed.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let profile = AgentSurfaceProfile(
            ownerCLI: "agent-wiki",
            skills: ["agent-wiki"],
            homes: [
                AgentHome(id: "codex", rootRelative: home.appendingPathComponent(".codex").path),
                AgentHome(id: "claude", rootRelative: home.appendingPathComponent(".claude").path),
            ]
        )

        // catalogRoots empty — must use seedRoot
        let result = try AgentSurfaceRules.attach(
            profile: profile,
            seedRoot: root.appendingPathComponent("seed"),
            catalogRoots: [root.appendingPathComponent("no-catalog")],
            home: home
        )
        #expect(result.errors.isEmpty)
        #expect(result.attached.count == 2)
        let st = AgentSurfaceRules.status(profile: profile, home: home)
        #expect(st.missing.isEmpty)
        #expect(st.installed.count == 2)
    }

    /// GUI .app layout: seed under Contents/Resources/<SPM>.bundle/plugin/<skill>/SKILL.md
    /// — Bundle.main.resourceURL 직속이 아니라 nested .bundle 을 찾아야 한다.
    @Test func resolveBundledSkillScansNestedResourceBundles() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("surface-nested-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: root) }

        let resources = root.appendingPathComponent("Resources", isDirectory: true)
        let nested = resources.appendingPathComponent("FakeApp_FakeCLI.bundle", isDirectory: true)
        let skillDir = nested.appendingPathComponent("plugin/agent-wiki", isDirectory: true)
        try fm.createDirectory(at: skillDir, withIntermediateDirectories: true)
        try "# agent-wiki seed\n".write(
            to: skillDir.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        // Minimal Bundle stub via Bundle(path:) — use a temp .bundle with Info.plist
        let appBundleDir = root.appendingPathComponent("Fake.app/Contents", isDirectory: true)
        try fm.createDirectory(at: appBundleDir.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
        try fm.createDirectory(at: appBundleDir.appendingPathComponent("Resources"), withIntermediateDirectories: true)
        // Place nested resource bundle where Bundle.resourceURL will point
        let resURL = appBundleDir.appendingPathComponent("Resources", isDirectory: true)
        try fm.createDirectory(
            at: resURL.appendingPathComponent("FakeApp_FakeCLI.bundle/plugin/agent-wiki", isDirectory: true),
            withIntermediateDirectories: true
        )
        try "# seed\n".write(
            to: resURL.appendingPathComponent("FakeApp_FakeCLI.bundle/plugin/agent-wiki/SKILL.md"),
            atomically: true,
            encoding: .utf8
        )
        let info = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
          <key>CFBundleIdentifier</key><string>test.fake.app</string>
          <key>CFBundleName</key><string>Fake</string>
          <key>CFBundleExecutable</key><string>Fake</string>
          <key>CFBundlePackageType</key><string>APPL</string>
        </dict></plist>
        """
        try info.write(to: appBundleDir.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)
        try Data().write(to: appBundleDir.appendingPathComponent("MacOS/Fake"))

        guard let bundle = Bundle(path: root.appendingPathComponent("Fake.app").path) else {
            Issue.record("Bundle(path:) failed")
            return
        }
        let found = AgentSurfaceRules.resolveBundledSkill(name: "agent-wiki", bundle: bundle)
        #expect(found != nil)
        #expect(found?.lastPathComponent == "agent-wiki")
        #expect(fm.fileExists(atPath: found!.appendingPathComponent("SKILL.md").path))
    }

    @Test func attachAgentsAndRefreshLeftoverCopy() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("surface-agents-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: root) }

        let home = root.appendingPathComponent("home", isDirectory: true)
        try fm.createDirectory(at: home.appendingPathComponent(".claude"), withIntermediateDirectories: true)
        let leftover = home.appendingPathComponent(".claude/skills/demo-helper", isDirectory: true)
        try fm.createDirectory(at: leftover, withIntermediateDirectories: true)
        try "# old leftover\n".write(to: leftover.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let seedSkill = root.appendingPathComponent("seed/demo-helper", isDirectory: true)
        try fm.createDirectory(at: seedSkill, withIntermediateDirectories: true)
        try "# new seed\n".write(to: seedSkill.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        let agentSeed = root.appendingPathComponent("agents")
        try fm.createDirectory(at: agentSeed, withIntermediateDirectories: true)
        try "# agent def\n".write(to: agentSeed.appendingPathComponent("demo-helper.md"), atomically: true, encoding: .utf8)

        let profile = AgentSurfaceProfile(
            ownerCLI: "demo",
            skills: ["demo-helper"],
            agents: ["demo-helper"],
            homes: [AgentHome(id: "claude", rootRelative: home.appendingPathComponent(".claude").path)],
            preferCatalogSymlink: false
        )
        let result = try AgentSurfaceRules.attach(
            profile: profile,
            seedRoot: root.appendingPathComponent("seed"),
            agentRoots: [agentSeed],
            catalogRoots: [root.appendingPathComponent("no-catalog")],
            home: home
        )
        #expect(result.errors.isEmpty)
        let refreshed = try String(
            contentsOf: leftover.appendingPathComponent("SKILL.md"),
            encoding: .utf8
        )
        #expect(refreshed.contains("new seed"))
        let agentOut = home.appendingPathComponent(".claude/agents/demo-helper.md")
        #expect(fm.fileExists(atPath: agentOut.path))
        #expect(result.attached.contains { $0.path.hasSuffix("agents/demo-helper.md") })
    }

    @Test func layoutDeclaresPerCLIAttachSurface() {
        #expect(AgentCLILayout.claude.attachesAgents)
        #expect(!AgentCLILayout.codex.attachesAgents)
        #expect(AgentCLILayout.codex.attachesSkills)
        #expect(AgentCLILayout.managed.map(\.id).contains("cursor"))
        #expect(Set(AgentHome.defaults.map(\.id)) == Set(AgentCLILayout.managed.map(\.id)))
        let unknown = AgentHome(id: "lab", rootRelative: ".lab")
        #expect(AgentCLILayout.forHome(unknown).attachesAgents)
        let roots = AgentSurfaceGate.scanRoots(
            userHome: URL(fileURLWithPath: "/home", isDirectory: true)
        )
        #expect(roots.contains { $0.hostId == "claude" && $0.via == "user agents" })
        #expect(!roots.contains { $0.hostId == "codex" && $0.via == "user agents" })
        #expect(roots.contains { $0.hostId == "grok" && $0.via == "bundled/skills" })
        let seeds = AgentSurfaceGate.Seeds.forApp(
            appDir: URL(fileURLWithPath: "/repo/apps/demo-swift"),
            repoRoot: URL(fileURLWithPath: "/repo")
        )
        #expect(seeds.skillRoots.contains { $0.path.hasSuffix(".claude/skills") })
        #expect(seeds.agentRoots.contains { $0.path.hasSuffix(".claude/agents") })
        #expect(AgentSurfaceGate.needsEmit(skills: ["gone"], agents: [], userHome: URL(fileURLWithPath: "/home")))
        let bridgeIDs: Set<String> = ["claude", "codex", "grok"]
        #expect(bridgeIDs.isSubset(of: Set(AgentCLILayout.managed.map(\.id))))
    }

    @Test func appSeedBeatsRepoKiroCatalogRoot() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("seed-order-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: root) }
        let home = root.appendingPathComponent("home", isDirectory: true)
        try fm.createDirectory(at: home.appendingPathComponent(".claude"), withIntermediateDirectories: true)
        let repoKiro = root.appendingPathComponent("repo-kiro/demo-helper", isDirectory: true)
        try fm.createDirectory(at: repoKiro, withIntermediateDirectories: true)
        try "# repo\n".write(to: repoKiro.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        let appSeed = root.appendingPathComponent("app-kiro/demo-helper", isDirectory: true)
        try fm.createDirectory(at: appSeed, withIntermediateDirectories: true)
        try "# app\n".write(to: appSeed.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        let profile = AgentSurfaceProfile(
            ownerCLI: "demo",
            skills: ["demo-helper"],
            homes: [AgentHome(id: "claude", rootRelative: home.appendingPathComponent(".claude").path)],
            preferCatalogSymlink: false
        )
        let result = try AgentSurfaceGate.attach(
            profile: profile,
            seeds: .init(
                catalogSeedRoot: root.appendingPathComponent("repo-kiro"),
                skillRoots: [root.appendingPathComponent("app-kiro")]
            ),
            catalogRoots: [root.appendingPathComponent("no-catalog")],
            home: home
        )
        #expect(result.errors.isEmpty)
        let text = try String(
            contentsOf: AgentCLILayout.claude.skillFile(
                name: "demo-helper",
                userHome: home
            ),
            encoding: .utf8
        )
        #expect(text.contains("app"))
        #expect(!text.contains("repo"))
    }
}
