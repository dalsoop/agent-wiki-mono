import Foundation
import AgentRegistryKit
import SkillRegistryKit

/// 한 앱에 해당하는 카드 전체를 모은다 — 파일 SSOT(agents.json, SKILL.md)를 읽어
/// CatalogCard 로 평탄화. GUI 카드뷰와 CLI --json 이 같은 catalog.cards() 를 소비한다.
///
/// 출처:
///   1. 전역 선언 에이전트 — AgentRegistry(~/.agent-apps/agents.json)
///   2. 워크스페이스 스킬 — apps/<slug>/.claude/skills/*/
///   3. 전역 스킬 — SkillRegistry.scanGlobal()
public struct AppCardCatalog: Sendable {
    public let appSlug: String
    public let workspaceRoot: URL?
    public let agents: AgentRegistry
    public let skills: SkillRegistry

    public init(appSlug: String,
                workspaceRoot: URL? = nil,
                agents: AgentRegistry = AgentRegistry(),
                skills: SkillRegistry = SkillRegistry()) {
        self.appSlug = appSlug
        self.workspaceRoot = workspaceRoot
        self.agents = agents
        self.skills = skills
    }

    public func cards() -> [any CatalogCard] {
        var out: [any CatalogCard] = []
        out += agents.load().map { AgentCard(def: $0) }
        if let root = workspaceRoot {
            out += scanWorkspaceSkills(in: root)
        }
        out += skills.scanGlobal().map { SkillCard(ref: $0) }
        return out
    }

    /// apps/<slug>/.claude/skills/<name>/ 스캔 — SkillRegistryKit 은 global 만 기본 지원하므로
    /// 워크스페이스 루트는 여기서 주입한다. dot/underscore 폴더 제외, SKILL.md 우선.
    func scanWorkspaceSkills(in root: URL) -> [SkillCard] {
        let dir = root.appendingPathComponent(".claude/skills")
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return [] }
        return entries
            .filter { !$0.hasPrefix(".") && !$0.hasPrefix("_") }
            .map { dir.appendingPathComponent($0) }
            .filter { (try? FileManager.default.attributesOfItem(atPath: $0.path)[.type] as? FileAttributeType) == .typeDirectory }
            .compactMap { skillDir -> SkillCard? in
                let name = skillDir.lastPathComponent
                let skillMD = skillDir.appendingPathComponent("SKILL.md")
                let path = FileManager.default.fileExists(atPath: skillMD.path) ? skillMD.path : skillDir.path
                let ref = SkillRef(id: SkillRegistry.makeID(tool: "claude", name: name),
                                   name: name, tool: "claude", path: path, scope: "workspace")
                return SkillCard(ref: ref)
            }
    }
}
