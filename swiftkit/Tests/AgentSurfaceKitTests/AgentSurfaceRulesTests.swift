import Foundation
import Testing
@testable import AgentSurfaceKit

@Suite struct AgentSurfaceRulesTests {
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
        #expect(!AgentSurfaceGate.needsEmit(skills: ["gone"], agents: ["gone"], userHome: URL(fileURLWithPath: "/home")))
        let bridgeIDs: Set<String> = ["claude", "codex", "grok"]
        #expect(bridgeIDs.isSubset(of: Set(AgentCLILayout.managed.map(\.id))))
    }

    // MARK: - 누수 금지 (앱은 스킬·에이전트를 홈에 싣지 않는다)

    private static let agentHomeDirs = [".claude", ".codex", ".grok", ".cursor", ".agents"]

    /// 임시 홈에 에이전트 홈 폴더가 이미 있어도(복사 조건 충족) 부착은 아무것도 쓰지 않는다.
    private struct LeakFixture {
        let root: URL
        let home: URL
        let profile: AgentSurfaceProfile
        let seed: URL
        let agentSeed: URL
        let catalog: URL
    }

    private func leakFixture() throws -> LeakFixture {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("surface-leak-\(UUID().uuidString)", isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        var homes: [AgentHome] = []
        for d in Self.agentHomeDirs {
            let dir = home.appendingPathComponent(d)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            homes.append(AgentHome(id: String(d.dropFirst()), rootRelative: dir.path))
        }
        let seedSkill = root.appendingPathComponent("seed/demo-helper", isDirectory: true)
        try fm.createDirectory(at: seedSkill, withIntermediateDirectories: true)
        try "# seed\n".write(to: seedSkill.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        let agentSeed = root.appendingPathComponent("agents", isDirectory: true)
        try fm.createDirectory(at: agentSeed, withIntermediateDirectories: true)
        try "# agent\n".write(to: agentSeed.appendingPathComponent("demo-helper.md"), atomically: true, encoding: .utf8)
        let catalogSkill = root.appendingPathComponent("catalog/skills/demo-helper", isDirectory: true)
        try fm.createDirectory(at: catalogSkill, withIntermediateDirectories: true)
        try "# catalog\n".write(to: catalogSkill.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        let profile = AgentSurfaceProfile(
            ownerCLI: "demo", skills: ["demo-helper"], agents: ["demo-helper"], homes: homes)
        return LeakFixture(
            root: root, home: home, profile: profile,
            seed: root.appendingPathComponent("seed"), agentSeed: agentSeed,
            catalog: root.appendingPathComponent("catalog"))
    }

    private func assertHomeUntouched(_ home: URL) throws {
        let fm = FileManager.default
        for d in Self.agentHomeDirs {
            let dir = home.appendingPathComponent(d)
            let entries = try fm.contentsOfDirectory(atPath: dir.path)
            #expect(entries.isEmpty, "\(d) 아래에 \(entries) 가 생겼다")
        }
        let top = try fm.contentsOfDirectory(atPath: home.path).sorted()
        #expect(top == Self.agentHomeDirs.sorted(), "홈 최상위에 새 항목: \(top)")
    }

    @Test func attachWritesNothingUnderAnyAgentHome() throws {
        let f = try leakFixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let rules = try AgentSurfaceRules.attach(
            profile: f.profile, seedRoot: f.seed, agentRoots: [f.agentSeed],
            catalogRoots: [f.catalog], home: f.home)
        #expect(rules.errors.isEmpty)
        #expect(rules.attached.isEmpty)
        #expect(rules.ok)
        let gate = try AgentSurfaceGate.attach(
            profile: f.profile,
            seeds: .init(catalogSeedRoot: f.seed, skillRoots: [f.seed], agentRoots: [f.agentSeed]),
            catalogRoots: [f.catalog], home: f.home)
        #expect(gate.errors.isEmpty)
        #expect(gate.attached.isEmpty)
        try assertHomeUntouched(f.home)
        #expect(AgentSurfaceRules.readManifest(ownerCLI: "demo", home: f.home) == nil)
    }

    @Test func attachDoesNotReplaceExistingLinkOrCopy() throws {
        let f = try leakFixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let fm = FileManager.default
        let existing = f.home.appendingPathComponent(".claude/skills/demo-helper", isDirectory: true)
        try fm.createDirectory(at: existing, withIntermediateDirectories: true)
        try "# user copy\n".write(to: existing.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        _ = try AgentSurfaceRules.attach(
            profile: f.profile, seedRoot: f.seed, agentRoots: [f.agentSeed],
            catalogRoots: [f.catalog], home: f.home)
        let text = try String(contentsOf: existing.appendingPathComponent("SKILL.md"), encoding: .utf8)
        #expect(text.contains("user copy"))
    }

    @Test func detachWritesNothing() throws {
        let f = try leakFixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let det = try AgentSurfaceRules.detach(profile: f.profile, home: f.home)
        #expect(det.errors.isEmpty)
        try assertHomeUntouched(f.home)
        #expect(AgentSurfaceRules.readManifest(ownerCLI: "demo", home: f.home) == nil)
    }

    @Test func coverageNeverDemandsSkillsOrAgents() {
        let home = URL(fileURLWithPath: "/nonexistent-home", isDirectory: true)
        let cov = AgentSurfaceGate.coverage(skills: ["gone", "gone-2"], agents: ["gone"], userHome: home)
        #expect(cov.missingSkills.isEmpty)
        #expect(cov.missingAgents.isEmpty)
        #expect(!cov.needsEmit)
        #expect(!AgentSurfaceGate.needsEmit(skills: ["gone"], agents: ["gone"], userHome: home))
    }

}
