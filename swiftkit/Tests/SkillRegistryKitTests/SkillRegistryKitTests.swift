import Testing
import Foundation
@testable import SkillRegistryKit

@Suite("SkillRegistryKit — 스킬 스캔·해석")
struct SkillRegistryKitTests {
    /// 임시 홈에 도구별 스킬 트리를 깐다.
    func makeHome(_ skills: [(tool: String, seg: [String], name: String, withMD: Bool)]) -> URL {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("skreg-\(UUID().uuidString)")
        for s in skills {
            let dir = s.seg.reduce(home) { $0.appendingPathComponent($1) }.appendingPathComponent(s.name)
            do { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) } catch { _ = error }
            if s.withMD {
                do { try "# skill".data(using: .utf8)!.write(to: dir.appendingPathComponent("SKILL.md")) } catch { _ = error }
            }
        }
        return home
    }

    @Test("id 규약 <tool>/<name>")
    func idRule() {
        #expect(SkillRegistry.makeID(tool: "claude", name: "wiki-record") == "claude/wiki-record")
    }

    @Test("globalDefaults 에 세 런타임이 있다")
    func catalogIncludesKnownRuntimes() {
        let ids = SkillToolRoot.globalDefaults.map(\.tool)
        #expect(ids.contains("claude"))
        #expect(ids.contains("codex"))
        #expect(ids.contains("grok"))
    }

    @Test("existingGlobalRootPaths 는 있는 디렉터리만")
    func existingRoots() {
        let home = makeHome([("grok", [".grok", "skills"], "x", true)])
        let paths = SkillRegistry(home: home).existingGlobalRootPaths()
        #expect(paths.count == 1)
        #expect(paths[0].hasSuffix(".grok/skills"))
    }

    @Test("global 스캔 — SKILL.md 있으면 그 경로, 없으면 디렉토리")
    func scan() {
        let home = makeHome([
            ("claude", [".claude", "skills"], "wiki-record", true),
            ("codex", [".codex", "skills"], "audit", false),
            ("grok", [".grok", "skills"], "caveman", true),
        ])
        let reg = SkillRegistry(home: home)
        let all = reg.scanGlobal()
        #expect(all.count == 3)
        let wiki = all.first { $0.id == "claude/wiki-record" }
        #expect(wiki?.path.hasSuffix("SKILL.md") == true)
        #expect(wiki?.scope == "global")
        let audit = all.first { $0.id == "codex/audit" }
        #expect(audit?.path.hasSuffix("audit") == true)  // MD 없음 → 디렉토리
        let grok = all.first { $0.id == "grok/caveman" }
        #expect(grok?.tool == "grok")
        #expect(grok?.path.hasSuffix("SKILL.md") == true)
    }

    @Test("숨김 디렉토리·빈 루트 무시")
    func ignores() {
        let home = makeHome([("claude", [".claude", "skills"], ".hidden", true)])
        #expect(SkillRegistry(home: home).scanGlobal().isEmpty)
        // 아예 없는 홈
        let empty = FileManager.default.temporaryDirectory.appendingPathComponent("nope-\(UUID().uuidString)")
        #expect(SkillRegistry(home: empty).scanGlobal().isEmpty)
    }

    @Test("resolve(ids:) — 존재하는 것만, 순서 보존")
    func resolveIDs() {
        let home = makeHome([
            ("claude", [".claude", "skills"], "a", true),
            ("claude", [".claude", "skills"], "b", true),
        ])
        let reg = SkillRegistry(home: home)
        let got = reg.resolve(ids: ["claude/b", "claude/missing", "claude/a"])
        #expect(got.map(\.name) == ["b", "a"])
        #expect(reg.resolve(id: "claude/missing") == nil)
    }
}
