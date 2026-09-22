import Foundation

/// 스킬 SSOT(읽기 계층) — "무슨 스킬이 있나"를 도구 경계 없이 하나로 노출한다.
///
/// 이 맥의 스킬은 도구마다 흩어져 있다(`~/.claude/skills`, `~/.codex/skills`, …).
/// `agent-skills` 앱이 이 흩어짐을 편집·동기화하는 SkillManager 라면, 이 Kit 은 그
/// 아래 의존층 — 다른 앱(AgentRegistryKit·Hermes)이 스킬 id 를 참조·해석할 수 있게
/// 하는 **최소 읽기 계약**이다. 점수·미리보기·동기화 같은 편집 기능은 앱에 남긴다.
public struct SkillRef: Sendable, Codable, Equatable, Identifiable, Hashable {
    /// 안정 id — "<tool>/<name>" (예: "claude/wiki-record"). 앱·잡이 이걸로 스킬을 가리킨다.
    public var id: String
    public var name: String
    public var tool: String
    public var path: String
    public var scope: String

    public init(id: String, name: String, tool: String, path: String, scope: String) {
        self.id = id; self.name = name; self.tool = tool; self.path = path; self.scope = scope
    }
}

/// 한 도구의 홈 스킬 폴더. 세그먼트만 둔다. 번역·조상 탐색은 소비자가 한다.
public struct SkillToolRoot: Sendable, Equatable {
    public var tool: String
    public var segments: [String]
    public init(tool: String, segments: [String]) { self.tool = tool; self.segments = segments }

    /// 이 맥의 표준 global 스킬 루트. 런타임을 더하면 여기 한 줄.
    public static let globalDefaults: [SkillToolRoot] = [
        .init(tool: "claude", segments: [".claude", "skills"]),
        .init(tool: "codex", segments: [".codex", "skills"]),
        .init(tool: "grok", segments: [".grok", "skills"]),
        .init(tool: "copilot", segments: [".copilot", "skills"]),
        .init(tool: "gemini", segments: [".gemini", "skills"]),
        .init(tool: "agents", segments: [".agents", "skills"]),
    ]
}

public struct SkillRegistry: Sendable {
    let home: URL
    let roots: [SkillToolRoot]
    private var fm: FileManager { .default }

    public static var defaultHome: URL {
        #if os(macOS)
        FileManager.default.homeDirectoryForCurrentUser
        #else
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        #endif
    }

    public init(home: URL = SkillRegistry.defaultHome,
                roots: [SkillToolRoot] = SkillToolRoot.globalDefaults) {
        self.home = home
        self.roots = roots
    }

    public static func makeID(tool: String, name: String) -> String { "\(tool)/\(name)" }

    public func existingGlobalRootPaths(fm: FileManager = .default) -> [String] {
        roots.compactMap { root in
            let dir = root.segments.reduce(home) { $0.appendingPathComponent($1) }.path
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dir, isDirectory: &isDir), isDir.boolValue else { return nil }
            return dir
        }
    }

    public func scanGlobal() -> [SkillRef] {
        var out: [SkillRef] = []
        for root in roots {
            let dir = root.segments.reduce(home) { $0.appendingPathComponent($1) }
            guard let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey]) else { continue }
            for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: entry.path, isDirectory: &isDir), isDir.boolValue else { continue }
                let name = entry.lastPathComponent
                if name.hasPrefix(".") { continue }
                let skillMD = Self.skillFile(in: entry, fm: fm)
                out.append(SkillRef(id: Self.makeID(tool: root.tool, name: name), name: name,
                                    tool: root.tool, path: (skillMD ?? entry).path, scope: "global"))
            }
        }
        return out
    }

    public func resolve(id: String) -> SkillRef? { scanGlobal().first { $0.id == id } }

    public func resolve(ids: [String]) -> [SkillRef] {
        let all = Dictionary(scanGlobal().map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return ids.compactMap { all[$0] }
    }

    static func skillFile(in dir: URL, fm: FileManager) -> URL? {
        guard let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return nil }
        return entries.first { $0.lastPathComponent.lowercased() == "skill.md" }
    }
}
