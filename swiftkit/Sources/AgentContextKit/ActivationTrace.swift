import Foundation
import AgentSessionKit
import SkillRegistryKit

/// 세션 도중 **끌려 들어온 md** 를 찾는다.
///
/// 루트 지침만 md 가 아니다. 스킬을 부르면 `SKILL.md` 가, 서브에이전트를 띄우면
/// `agents/<name>.md` 가 그 순간 컨텍스트로 들어간다. 이름만 세면(`skills: [a, b]`)
/// "무슨 문서가 물렸나" 라는 원래 질문에 반만 답한 것이다. 그래서 활성화 이벤트를
/// 파일 경로까지 해석한다.
public enum ActivationTrace {
    /// 스킬 이름 → `SKILL.md` 경로.
    ///
    /// 탐색 순서는 실제 로딩 우선순위를 따른다: 프로젝트 로컬 → 홈. 플러그인 스킬은
    /// `plugin:skill` 로 오므로 뒤쪽 이름으로 한 번 더 찾는다.
    public static func skillPath(_ name: String, cwd: String, home: String = NSHomeDirectory(),
                                 fm: FileManager = .default) -> String? {
        let bare = name.contains(":") ? String(name.split(separator: ":").last!) : name
        // 프로젝트 로컬 스킬은 cwd 바로 밑이 아니라 **워크스페이스 조상**에 있다
        // (실측: `WORKSPACE/.claude/skills/…` 인데 cwd 는 그 아래 레포였다).
        var roots: [String] = []
        let catalog = SkillToolRoot.globalDefaults
        var ancestor = (cwd as NSString).standardizingPath
        while ancestor.count > 1 {
            for tool in catalog {
                roots.append(([ancestor] + tool.segments).joined(separator: "/"))
            }
            ancestor = (ancestor as NSString).deletingLastPathComponent
        }
        roots += SkillRegistry(home: URL(fileURLWithPath: home)).existingGlobalRootPaths()
        // 플러그인 스킬은 플러그인 디렉터리 아래 산다. 이름이 `plugin:skill` 이면 그 플러그인만 본다.
        if name.contains(":"), let plugin = name.split(separator: ":").first {
            roots.append(home + "/.claude/plugins/\(plugin)/skills")
            roots.append(home + "/.claude/plugins/repos/\(plugin)/skills")
        }
        for root in roots {
            for candidate in [root + "/\(name)/SKILL.md", root + "/\(bare)/SKILL.md"] {
                if fm.fileExists(atPath: candidate) { return (candidate as NSString).standardizingPath }
            }
        }
        // SkillRegistryKit — 홈 전역 스킬 루트 정본(claude/codex/grok/copilot/gemini/agents).
        if let ref = SkillRegistry(home: URL(fileURLWithPath: home)).scanGlobal()
            .first(where: { $0.name == bare || $0.id == name }) {
            let md = ref.path.hasSuffix(".md") ? ref.path : ref.path + "/SKILL.md"
            if fm.fileExists(atPath: md) { return (md as NSString).standardizingPath }
        }
        return nil
    }

    /// 정의 md 가 **없는 게 정상**인 내장 스킬.
    ///
    /// CLI 바이너리 안에 실려 오는 스킬이라 디스크에 `SKILL.md` 가 없다. 이걸 구분 안
    /// 하면 "정의 못 찾음" 경고로 떠서, 삭제된 스킬을 부른 **진짜** 사고와 뒤섞인다.
    /// 확인법: `strings $(readlink -f $(which claude)) | grep <이름>`
    /// (실측 2026-08-04, claude 2.1.221 에서 셋 다 바이너리에 들어 있음).
    public static let bundledSkills: Set<String> = [
        "artifact-design", "artifact-diagramming", "claude-api",
    ]

    /// 정의 md 가 **없는 게 정상**인 내장 에이전트.
    ///
    /// 이 목록은 **힌트지 판정 근거가 아니다.** 런타임 버전마다 내장 목록이 바뀌므로
    /// 하드코딩에 판정을 맡기면 남의 맥에서 틀린다. 실제 판정은 `verdict(for:)` 가
    /// 파일 시스템을 보고 내린다.
    public static let knownBuiltinAgents: Set<String> = [
        "general-purpose", "Explore", "Plan", "claude", "statusline-setup", "fork",
    ]

    /// 정의 md 를 못 찾았을 때, 그게 정상인지 이상인지.
    public enum MissingVerdict: Sendable, Equatable {
        /// 이 맥에 에이전트 정의 디렉터리 자체가 없다 → 전부 내장이다. 정상.
        case noAgentDirectory
        /// 알려진 내장 이름이다. 정상.
        case knownBuiltin
        /// 정의 디렉터리에 **다른** 에이전트들은 있는데 이것만 없다 → 삭제됐거나 오타. 이상.
        case likelyDeleted(siblings: Int)
    }

    /// 못 찾은 이유를 **파일 시스템에 물어서** 판정한다.
    ///
    /// 왜 목록만으로 안 되나 — 삭제된 스킬·에이전트를 부른 흔적이 실제로 존재하고
    /// (`.trash-ssot-switch/…/SKILL.md`), 그게 진짜 잡아야 할 신호다. 하드코딩 목록에
    /// 없다는 이유로 전부 경고를 띄우면 내장 스폰 24회가 화면을 도배해 신호가 죽는다.
    public static func verdict(forMissing name: String, kind: Activation.Kind,
                               cwd: String, home: String = NSHomeDirectory(),
                               fm: FileManager = .default) -> MissingVerdict {
        if kind == .subagent, knownBuiltinAgents.contains(name) { return .knownBuiltin }

        let dirs = kind == .subagent
            ? [cwd + "/.claude/agents", home + "/.claude/agents"]
            : SkillRegistry(home: URL(fileURLWithPath: home)).existingGlobalRootPaths()
                + [cwd + "/.claude/skills"]
        var siblings = 0
        var anyDir = false
        for dir in dirs {
            guard let names = directoryEntries(fm, dir) else { continue }
            anyDir = true
            siblings += names.filter { $0 != ".DS_Store" }.count
        }
        guard anyDir, siblings > 0 else { return .noAgentDirectory }
        return .likelyDeleted(siblings: siblings)
    }

    /// 서브에이전트 타입 → 정의 md 경로.
    public static func agentPath(_ name: String, cwd: String, home: String = NSHomeDirectory(),
                                 fm: FileManager = .default) -> String? {
        for root in [cwd + "/.claude/agents", home + "/.claude/agents",
                     cwd + "/.codex/agents", home + "/.codex/agents"] {
            let candidate = root + "/\(name).md"
            if fm.fileExists(atPath: candidate) { return (candidate as NSString).standardizingPath }
        }
        return nil
    }

    /// 활성화 이벤트를 `InjectedDoc` 스택으로 바꾼다. 층은 `skill` · `agent`.
    ///
    /// provenance 는 `read` — 재구성이 아니라 세션이 실제로 그걸 불렀다는 관측이다.
    /// (파일을 못 찾으면 `missing` 으로 남긴다. 삭제된 스킬을 부른 흔적도 사실이다 —
    /// 실제로 세션 로그에 `.trash-ssot-switch/…/SKILL.md` 접근이 남아 있었다.)
    public static func docs(from activations: [Activation], cwd: String,
                            home: String = NSHomeDirectory(), fm: FileManager = .default) -> [InjectedDoc] {
        var out: [InjectedDoc] = []
        var seen = Set<String>()
        for a in activations {
            let path: String?
            switch a.kind {
            case .skill: path = skillPath(a.name, cwd: cwd, home: home, fm: fm)
            case .subagent: path = agentPath(a.name, cwd: cwd, home: home, fm: fm)
            }
            guard let path, seen.insert(path).inserted else { continue }
            let data = fm.contents(atPath: path)
            let text = data.flatMap { String(data: $0, encoding: .utf8) }
            out.append(InjectedDoc(
                path: path, layer: a.kind.rawValue, provenance: .read,
                bytes: data?.count, approxTokens: text.map(TokenEstimate.approxTokens),
                missing: data == nil
            ))
        }
        return out
    }
}

/// 없거나 못 읽는 디렉터리는 nil — 사각지대 판정에서 "디렉터리 없음" 으로 친다.
private func directoryEntries(_ fm: FileManager, _ dir: String) -> [String]? {
    do {
        return try fm.contentsOfDirectory(atPath: dir)
    } catch {
        return nil  // 권한 없음·없음 둘 다 "여기엔 없다".
    }
}

/// 세션 도중의 활성화 1건 — 무엇을, 몇 번째 이벤트에서, 직전에 무슨 생각을 하고 불렀나.
public struct Activation: Sendable, Codable, Equatable {
    public enum Kind: String, Sendable, Codable { case skill, subagent }

    /// 신호의 강도. `invoked` 는 런타임이 "이 스킬을 쓴다" 고 기록한 것(Claude `Skill` 도구·
    /// `<command-name>`), `loaded` 는 SKILL.md 를 읽었다는 것뿐이다(codex·grok·agy 는 이게 전부).
    /// 둘을 같은 줄에 세면 스킬 감사 세션 하나가 설치된 스킬 전부를 "사용" 으로 올린다.
    public enum Source: String, Sendable, Codable { case invoked, loaded }

    public let kind: Kind
    public let name: String
    /// 세션 안 순번(시간축 대용). 로그마다 타임스탬프 유무가 달라 순번이 더 안정적이다.
    public let at: Int
    /// 직전 사고 블록 요약. 이게 "왜 이걸 불렀나" 에 가장 가까운 관측 증거다.
    public let thought: String?
    /// 해석된 정의 md 경로(못 찾으면 nil).
    public let mdPath: String?
    public let source: Source
    /// 같은 세션이 스킬을 **뭉텅이로** 읽었을 때 붙는다(카탈로그 감사·전수 grep). 집계에서 뺀다.
    public let bulk: Bool

    public init(kind: Kind, name: String, at: Int, thought: String?, mdPath: String?,
                source: Source = .loaded, bulk: Bool = false) {
        self.kind = kind
        self.name = name
        self.at = at
        self.thought = thought
        self.mdPath = mdPath
        self.source = source
        self.bulk = bulk
    }

    /// 같은 활성화를 bulk 로 표시한 사본.
    public func markedBulk() -> Activation {
        Activation(kind: kind, name: name, at: at, thought: thought, mdPath: mdPath, source: source, bulk: true)
    }

    private enum CodingKeys: String, CodingKey { case kind, name, at, thought, mdPath, source, bulk }

    /// `source`·`bulk` 는 2026-09-03 에 추가됐다 — 그 전 JSON 도 읽힌다.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(Kind.self, forKey: .kind)
        name = try c.decode(String.self, forKey: .name)
        at = try c.decode(Int.self, forKey: .at)
        thought = try c.decodeIfPresent(String.self, forKey: .thought)
        mdPath = try c.decodeIfPresent(String.self, forKey: .mdPath)
        source = try c.decodeIfPresent(Source.self, forKey: .source) ?? .loaded
        bulk = try c.decodeIfPresent(Bool.self, forKey: .bulk) ?? false
    }
}
