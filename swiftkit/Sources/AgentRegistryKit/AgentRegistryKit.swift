import Foundation
import SkillRegistryKit

/// 에이전트 SSOT — **선언된(declared)** 에이전트. 실행 중 프로세스(AgentScanKit 의 RunningAgent)가
/// 아니라 "이런 에이전트를 이렇게 돌려라"는 재사용 가능한 정의다.
///
/// 한 AgentDef = 페르소나 + 실행 파일 + 모델 + 권한 모드 + 기본 cwd + 스킬셋.
/// AgentManager(agent-deck)가 이걸 편집하고, Hermes·worktree-control-terminal 이
/// `id` 로 참조해 실제 실행 사양을 조립한다. 이 의존 방향이 재편의 핵심이다.
public struct AgentDef: Sendable, Codable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var persona: String?        // 가명(승인 목록·로그 표기). 예: "새벽 갈까마귀"
    public var personaEmoji: String?   // 예: "🐦‍⬛"
    public var agent: String           // 실행 파일 — "claude" | "codex" | …
    public var model: String?          // 예: "claude-opus-4-8"
    public var permissionMode: String? // "acceptEdits" | "plan" | "bypassPermissions" | …
    public var defaultCwd: String?     // 기본 작업 디렉토리(잡이 override 가능)
    public var skillIDs: [String]      // SkillRegistryKit 의 스킬 id 참조("claude/wiki-record" …)
    public var notes: String?

    public struct Identity: Sendable, Codable, Equatable {
        public var id: String
        public var name: String
        public var persona: String?
        public var personaEmoji: String?

        public init(
            id: String = UUID().uuidString,
            name: String,
            persona: String? = nil,
            personaEmoji: String? = nil
        ) {
            self.id = id
            self.name = name
            self.persona = persona
            self.personaEmoji = personaEmoji
        }
    }

    public struct Runtime: Sendable, Codable, Equatable {
        public var agent: String
        public var model: String?
        public var permissionMode: String?
        public var defaultCwd: String?

        public init(
            agent: String = "claude",
            model: String? = nil,
            permissionMode: String? = "acceptEdits",
            defaultCwd: String? = nil
        ) {
            self.agent = agent
            self.model = model
            self.permissionMode = permissionMode
            self.defaultCwd = defaultCwd
        }
    }

    public init(
        identity: Identity,
        runtime: Runtime = Runtime(),
        skillIDs: [String] = [],
        notes: String? = nil
    ) {
        self.id = identity.id
        self.name = identity.name
        self.persona = identity.persona
        self.personaEmoji = identity.personaEmoji
        self.agent = runtime.agent
        self.model = runtime.model
        self.permissionMode = runtime.permissionMode
        self.defaultCwd = runtime.defaultCwd
        self.skillIDs = skillIDs
        self.notes = notes
    }

    /// 하위호환 — 축을 직접 나열하는 옛 호출부(agent-deck 등 함대 8곳)도 그대로
    /// 컴파일된다. 새 코드는 `identity:/runtime:` 그룹 이니셜라이저로 쓴다.
    public init(
        id: String = UUID().uuidString,
        name: String,
        persona: String? = nil,
        personaEmoji: String? = nil,
        agent: String = "claude",
        model: String? = nil,
        permissionMode: String? = "acceptEdits",
        defaultCwd: String? = nil,
        skillIDs: [String] = [],
        notes: String? = nil
    ) {
        self.init(
            identity: Identity(id: id, name: name, persona: persona, personaEmoji: personaEmoji),
            runtime: Runtime(agent: agent, model: model, permissionMode: permissionMode,
                defaultCwd: defaultCwd),
            skillIDs: skillIDs,
            notes: notes)
    }
}

/// 해석된 에이전트 — AgentDef + 실체화된 스킬 참조. 소비자(Hermes)가 실행 사양을 조립할 때 쓴다.
public struct ResolvedAgent: Sendable, Equatable {
    public let def: AgentDef
    public let skills: [SkillRef]
    public init(def: AgentDef, skills: [SkillRef]) { self.def = def; self.skills = skills }

    /// 프롬프트 머리에 붙일 페르소나·스킬 힌트(무상태 사이클이 자기 정체성·도구를 알게).
    /// 비면 빈 문자열 — 소비자가 프롬프트 앞에 그대로 붙이면 된다.
    public var promptPreamble: String {
        var lines: [String] = []
        if let p = def.persona {
            lines.append("너의 가명은 \(def.personaEmoji.map { "\($0) " } ?? "")\(p) 다.")
        }
        if !skills.isEmpty {
            let names = skills.map { $0.name }.joined(separator: ", ")
            lines.append("사용 가능한 스킬: \(names).")
        }
        return lines.joined(separator: "\n")
    }
}

/// agents.json 봉투 — 스키마 진화를 위한 버전 필드.
struct AgentRegistryFile: Codable {
    var version: Int
    var agents: [AgentDef]
}

/// ~/.agent-apps/agents.json 을 읽고 쓰는 저장소. 원자적 쓰기(임시파일→rename).
public struct AgentRegistry: Sendable {
    public let url: URL
    private let skills: SkillRegistry
    private var fm: FileManager { .default }

    public init(url: URL? = nil, skills: SkillRegistry = SkillRegistry()) {
        self.url = url ?? SkillRegistry.defaultHome
            .appendingPathComponent(".agent-apps/agents.json")
        self.skills = skills
    }

    public func load() -> [AgentDef] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        do {
            let file = try JSONDecoder().decode(AgentRegistryFile.self, from: data)
            return file.agents
        } catch {
            return []
        }
    }

    public func save(_ agents: [AgentDef]) throws {
        let file = AgentRegistryFile(version: 1, agents: agents)
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try enc.encode(file)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let tmp = url.deletingLastPathComponent().appendingPathComponent(".agents.json.\(UUID().uuidString).tmp")
        try data.write(to: tmp)
        do { try fm.removeItem(at: url) } catch {}
        try fm.moveItem(at: tmp, to: url)
    }

    /// id 로 upsert(같은 id 있으면 교체, 없으면 추가). 순서 보존.
    @discardableResult
    public func upsert(_ def: AgentDef) throws -> [AgentDef] {
        var agents = load()
        if let i = agents.firstIndex(where: { $0.id == def.id }) { agents[i] = def }
        else { agents.append(def) }
        try save(agents)
        appendHistory(kind: "upsert", def: def)
        return agents
    }

    @discardableResult
    public func remove(id: String) throws -> [AgentDef] {
        let removed = load().first { $0.id == id }
        let agents = load().filter { $0.id != id }
        try save(agents)
        if let removed { appendHistory(kind: "remove", def: removed) }
        return agents
    }

    // MARK: - 정의 이력 (append-only)

    /// `~/.agent-apps/agents-history.jsonl` — 정의가 바뀔 때마다 그 시점 전문을 덧쓴다.
    ///
    /// `agents.json` 은 덮어쓰기라, 캐릭터의 모델을 바꾸면 **어제 실적이 어느 정의로
    /// 낸 것인지 알 수 없었다**(wayfinder #41). 사건 원장이 `usedVersions` 를 박아도
    /// 정의 쪽에 버전이 없으면 반쪽이다. 이력의 줄 번호가 곧 그 캐릭터의 버전이다:
    /// `agents-md-filler@v3` = 이 파일에서 그 id 의 3번째 기록.
    ///
    /// 이력 쓰기 실패는 upsert 를 깨뜨리지 않는다 — 명부가 본체고 이력은 부가다.
    /// 다만 조용히 삼키지 않고 stderr 로 말한다.
    public var historyURL: URL {
        url.deletingLastPathComponent().appendingPathComponent("agents-history.jsonl")
    }

    private func appendHistory(kind: String, def: AgentDef) {
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        let defObj: Any
        do {
            let defData = try enc.encode(def)
            defObj = try JSONSerialization.jsonObject(with: defData)
        } catch {
            return
        }
        let entry: [String: Any] = [
            "at": ISO8601DateFormatter().string(from: Date()),
            "kind": kind,
            "id": def.id,
            "version": historyCount(id: def.id) + 1,
            "def": defObj,
        ]
        let line: Data
        do {
            line = try JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys])
        } catch {
            return
        }
        do {
            let handle: FileHandle?
            do {
                handle = try FileHandle(forWritingTo: historyURL)
            } catch {
                handle = nil
            }
            if let handle {
                defer { do { try handle.close() } catch {} }
                try handle.seekToEnd()
                try handle.write(contentsOf: line + Data("\n".utf8))
            } else {
                try (line + Data("\n".utf8)).write(to: historyURL)
            }
        } catch {
            FileHandle.standardError.write(Data("경고: 에이전트 이력 기록 실패 — \(error)\n".utf8))
        }
    }

    /// 그 id 의 이력 줄 수 — 다음 버전 번호의 근거.
    public func historyCount(id: String) -> Int {
        guard let text = try? String(contentsOf: historyURL, encoding: .utf8) else { return 0 }
        return text.split(separator: "\n").filter { line in
            guard let data = line.data(using: .utf8) else { return false }
            do {
                guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
                return obj["id"] as? String == id
            } catch {
                return false
            }
        }.count
    }

    /// 현재 버전 표기 — 사건의 usedVersions 에 넣을 값. 이력이 없으면 v0(기록 전 정의).
    public func versionTag(id: String) -> String {
        "\(id)@v\(historyCount(id: id))"
    }

    public func find(id: String) -> AgentDef? { load().first { $0.id == id } }

    /// id 로 에이전트를 스킬까지 실체화. 없으면 nil. Hermes 가 잡의 agentRef 를 이걸로 푼다.
    public func resolve(id: String) -> ResolvedAgent? {
        guard let def = find(id: id) else { return nil }
        return ResolvedAgent(def: def, skills: skills.resolve(ids: def.skillIDs))
    }
}
