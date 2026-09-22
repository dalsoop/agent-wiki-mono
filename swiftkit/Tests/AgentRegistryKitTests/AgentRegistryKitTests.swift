import Testing
import Foundation
@testable import AgentRegistryKit
@testable import SkillRegistryKit

@Suite("AgentRegistryKit — 선언 에이전트 SSOT")
struct AgentRegistryKitTests {
    func tmpURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("agreg-\(UUID().uuidString)/agents.json")
    }

    @Test("save→load 왕복")
    func roundtrip() throws {
        let reg = AgentRegistry(url: tmpURL())
        let a = AgentDef(
            identity: .init(name: "야간 수리공", persona: "새벽 갈까마귀", personaEmoji: "🐦‍⬛"),
            runtime: .init(model: "claude-opus-4-8"),
            skillIDs: ["claude/wiki-record"]
        )
        try reg.save([a])
        let back = reg.load()
        #expect(back == [a])
    }

    @Test("upsert — 같은 id 교체, 새 id 추가, 순서 보존")
    func upsert() throws {
        let reg = AgentRegistry(url: tmpURL())
        var a = AgentDef(identity: .init(id: "x", name: "A"))
        let b = AgentDef(identity: .init(id: "y", name: "B"))
        try reg.upsert(a); try reg.upsert(b)
        a.name = "A2"
        let out = try reg.upsert(a)
        #expect(out.map(\.id) == ["x", "y"])
        #expect(reg.find(id: "x")?.name == "A2")
    }

    @Test("remove")
    func remove() throws {
        let reg = AgentRegistry(url: tmpURL())
        try reg.upsert(AgentDef(identity: .init(id: "x", name: "A")))
        try reg.upsert(AgentDef(identity: .init(id: "y", name: "B")))
        let out = try reg.remove(id: "x")
        #expect(out.map(\.id) == ["y"])
    }

    @Test("빈/없는 파일 → 빈 목록")
    func emptyFile() {
        #expect(AgentRegistry(url: tmpURL()).load().isEmpty)
    }

    @Test("resolve — 스킬까지 실체화 + 프롬프트 프리앰블")
    func resolve() throws {
        // 스킬 트리
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("h-\(UUID().uuidString)")
        let dir = home.appendingPathComponent(".claude/skills/wiki-record")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "x".data(using: .utf8)!.write(to: dir.appendingPathComponent("SKILL.md"))

        let reg = AgentRegistry(url: tmpURL(), skills: SkillRegistry(home: home))
        try reg.upsert(AgentDef(
            identity: .init(id: "n", name: "야공", persona: "갈까마귀", personaEmoji: "🐦‍⬛"),
            skillIDs: ["claude/wiki-record", "claude/missing"]
        ))
        let r = reg.resolve(id: "n")
        #expect(r?.skills.map(\.name) == ["wiki-record"])   // missing 제외
        #expect(r?.promptPreamble.contains("갈까마귀") == true)
        #expect(r?.promptPreamble.contains("wiki-record") == true)
        #expect(reg.resolve(id: "없음") == nil)
    }
}
