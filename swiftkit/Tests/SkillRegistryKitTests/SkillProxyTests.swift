import Testing
import Foundation
@testable import SkillRegistryKit

@Suite("SkillProxy — 단방향 스킬 캐스케이드 해석 및 CoW")
struct SkillProxyTests {
    private func createTempDir(prefix: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("\(prefix)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func createSkill(in baseDir: URL, name: String, content: String? = nil) throws {
        let skillDir = baseDir.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        let skillFile = skillDir.appendingPathComponent("SKILL.md")
        let text = content ?? "# \(name)"
        guard let data = text.data(using: .utf8) else { return }
        try data.write(to: skillFile)
    }

    @Test("단방향 캐스케이드 해석: Room Local > Tenant > Global")
    func cascadePrecedence() throws {
        let globalHome = try createTempDir(prefix: "global-home")
        let globalClaudeSkills = globalHome.appendingPathComponent(".claude").appendingPathComponent("skills")
        try createSkill(in: globalClaudeSkills, name: "code-review", content: "global code review")
        try createSkill(in: globalClaudeSkills, name: "deploy-app", content: "global deploy")

        let tenantSkills = try createTempDir(prefix: "tenant-skills")
        try createSkill(in: tenantSkills, name: "deploy-app", content: "tenant custom deploy")
        try createSkill(in: tenantSkills, name: "tenant-only", content: "tenant exclusive")

        let roomSkills = try createTempDir(prefix: "room-skills")
        try createSkill(in: roomSkills, name: "code-review", content: "room local review")

        let globalRegistry = SkillRegistry(
            home: globalHome,
            roots: [.init(tool: "claude", segments: [".claude", "skills"])]
        )

        let proxy = SkillProxy(
            roomSkillsURL: roomSkills,
            tenantSkillsURL: tenantSkills,
            globalRegistry: globalRegistry
        )

        // 1. code-review 는 Room Local 과 Global 에 모두 존재 -> Room Local 이 이겨야 함
        let resolvedLocal = proxy.resolve(name: "code-review")
        #expect(resolvedLocal != nil)
        #expect(resolvedLocal?.layer == .roomLocal)
        #expect(resolvedLocal?.scope == "room")

        // 2. deploy-app 은 Tenant 와 Global 에 존재 -> Tenant 가 이겨야 함
        let resolvedTenant = proxy.resolve(name: "deploy-app")
        #expect(resolvedTenant != nil)
        #expect(resolvedTenant?.layer == .tenant)
        #expect(resolvedTenant?.scope == "tenant")

        // 3. tenant-only 는 Tenant 에만 존재
        let resolvedTenantOnly = proxy.resolve(name: "tenant-only")
        #expect(resolvedTenantOnly != nil)
        #expect(resolvedTenantOnly?.layer == .tenant)

        // 4. 없는 스킬은 nil
        #expect(proxy.resolve(name: "non-existent") == nil)
    }

    @Test("resolveAll: 우선순위 반영 병합")
    func resolveAllAggregation() throws {
        let globalHome = try createTempDir(prefix: "global-home")
        let globalSkills = globalHome.appendingPathComponent(".claude").appendingPathComponent("skills")
        try createSkill(in: globalSkills, name: "skill-a", content: "global a")
        try createSkill(in: globalSkills, name: "skill-b", content: "global b")

        let tenantSkills = try createTempDir(prefix: "tenant-skills")
        try createSkill(in: tenantSkills, name: "skill-b", content: "tenant b")
        try createSkill(in: tenantSkills, name: "skill-c", content: "tenant c")

        let roomSkills = try createTempDir(prefix: "room-skills")
        try createSkill(in: roomSkills, name: "skill-c", content: "room c")

        let proxy = SkillProxy(
            roomSkillsURL: roomSkills,
            tenantSkillsURL: tenantSkills,
            globalRegistry: SkillRegistry(home: globalHome, roots: [.init(tool: "claude", segments: [".claude", "skills"])])
        )

        let all = proxy.resolveAll()
        #expect(all.count == 3)

        let a = all.first { $0.name == "skill-a" }
        #expect(a?.layer == .global)

        let b = all.first { $0.name == "skill-b" }
        #expect(b?.layer == .tenant)

        let c = all.first { $0.name == "skill-c" }
        #expect(c?.layer == .roomLocal)
    }

    @Test("Copy-on-Write (materialize): 상위 스킬을 룸 로컬로 안전 복제")
    func materializeCopyOnWrite() throws {
        let globalHome = try createTempDir(prefix: "global-home")
        let globalSkills = globalHome.appendingPathComponent(".claude").appendingPathComponent("skills")
        try createSkill(in: globalSkills, name: "shared-tool", content: "# Shared Tool\nOriginal")

        let roomSkills = try createTempDir(prefix: "room-skills")

        let proxy = SkillProxy(
            roomSkillsURL: roomSkills,
            tenantSkillsURL: nil,
            globalRegistry: SkillRegistry(home: globalHome, roots: [.init(tool: "claude", segments: [".claude", "skills"])])
        )

        // 처음에는 global 로 해석
        let before = proxy.resolve(name: "shared-tool")
        #expect(before?.layer == .global)

        // materialize 실행 -> 룸 로컬로 복사됨
        let materialized = try proxy.materialize(skillName: "shared-tool")
        #expect(materialized.layer == .roomLocal)
        #expect(materialized.path.contains(roomSkills.path))

        // 이제 resolve 하면 roomLocal 로 해석
        let after = proxy.resolve(name: "shared-tool")
        #expect(after?.layer == .roomLocal)

        // 룸 로컬 파일 내용 수정 시 글로벌은 영향 없음
        let localSkillFile = URL(fileURLWithPath: materialized.path)
        guard let modData = "Modified locally".data(using: .utf8) else { return }
        try modData.write(to: localSkillFile)

        let localContent = try String(contentsOf: localSkillFile, encoding: .utf8)
        let globalSkillFile = globalSkills.appendingPathComponent("shared-tool").appendingPathComponent("SKILL.md")
        let globalContent = try String(contentsOf: globalSkillFile, encoding: .utf8)

        #expect(localContent == "Modified locally")
        #expect(globalContent == "# Shared Tool\nOriginal")
    }

    @Test("materialize: 이미 로컬에 있으면 기존 로컬 반환")
    func materializeExistingLocal() throws {
        let roomSkills = try createTempDir(prefix: "room-skills")
        try createSkill(in: roomSkills, name: "local-skill", content: "original local")

        let proxy = SkillProxy(roomSkillsURL: roomSkills)
        let mat = try proxy.materialize(skillName: "local-skill")
        #expect(mat.layer == .roomLocal)
        #expect(mat.name == "local-skill")
    }

    @Test("materialize: 존재하지 않는 스킬은 에러")
    func materializeNonExistent() throws {
        let roomSkills = try createTempDir(prefix: "room-skills")
        let proxy = SkillProxy(roomSkillsURL: roomSkills)

        #expect(throws: SkillProxyError.self) {
            try proxy.materialize(skillName: "ghost-skill")
        }
    }
}
