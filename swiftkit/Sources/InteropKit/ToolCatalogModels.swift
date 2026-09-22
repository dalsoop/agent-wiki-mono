import Foundation

/// 도구 종류 (앱, 스킬, 에이전트).
public enum ToolKind: String, Codable, Equatable, Sendable, CaseIterable {
    case app
    case skill
    case agent
}

/// 검색 결과 상태. `hits` 가 비어도 이유를 구분한다.
public enum CapabilitySearchStatus: String, Codable, Equatable, Sendable {
    /// 정상 질의. hits 는 0개 이상.
    case ok
    /// 질의 문자열이 비었거나 토큰이 없다.
    case emptyQuery
    /// registry.json 파일이 없다.
    case registryMissing
    /// 파일은 있으나 apps 가 비어 있다.
    case registryEmpty
    /// 질의는 유효하나 매칭 도구가 없다.
    case noMatches
    /// 모든 토큰을 만족하는 도구는 없지만, 일부 토큰으로 찾은 것이 있다.
    case partialMatches
}

/// 필드 단위 매칭 근거 — 사용자가 "왜 나왔는지" 판단할 수 있게.
public struct CapabilityMatchReason: Codable, Equatable, Sendable {
    public let field: String
    public let token: String
    public let snippet: String

    public init(field: String, token: String, snippet: String) {
        self.field = field
        self.token = token
        self.snippet = snippet
    }
}

/// 질의와 맞닿은 명령 한 줄.
public struct CapabilityMatchedCommand: Codable, Equatable, Sendable {
    public let name: String
    public let summary: String
    public let json: Bool

    public init(name: String, summary: String, json: Bool) {
        self.name = name
        self.summary = summary
        self.json = json
    }
}

/// 도구(앱/스킬/에이전트) 단위 검색 히트.
public struct CapabilitySearchHit: Codable, Equatable, Sendable {
    public typealias ToolKind = InteropKit.ToolKind

    public let name: String
    public let cli: String
    public let version: String
    public let matchedCommands: [CapabilityMatchedCommand]
    public let reasons: [CapabilityMatchReason]
    public let score: Int
    public let kind: ToolKind
    public let sourceID: String
    public var badge: String { "[\(kind.rawValue)]" }

    public init(
        name: String,
        cli: String,
        version: String,
        matchedCommands: [CapabilityMatchedCommand],
        reasons: [CapabilityMatchReason],
        score: Int,
        kind: ToolKind = .app,
        sourceID: String? = nil
    ) {
        self.name = name
        self.cli = cli
        self.version = version
        self.matchedCommands = matchedCommands
        self.reasons = reasons
        self.score = score
        self.kind = kind
        self.sourceID = sourceID ?? cli
    }

    enum CodingKeys: String, CodingKey {
        case name, cli, version, matchedCommands, reasons, score, kind, sourceID, badge
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
        self.cli = try container.decode(String.self, forKey: .cli)
        self.version = try container.decode(String.self, forKey: .version)
        self.matchedCommands = try container.decode([CapabilityMatchedCommand].self, forKey: .matchedCommands)
        self.reasons = try container.decode([CapabilityMatchReason].self, forKey: .reasons)
        self.score = try container.decode(Int.self, forKey: .score)
        self.kind = try container.decodeIfPresent(ToolKind.self, forKey: .kind) ?? .app
        self.sourceID = try container.decodeIfPresent(String.self, forKey: .sourceID) ?? self.cli
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(cli, forKey: .cli)
        try container.encode(version, forKey: .version)
        try container.encode(matchedCommands, forKey: .matchedCommands)
        try container.encode(reasons, forKey: .reasons)
        try container.encode(score, forKey: .score)
        try container.encode(kind, forKey: .kind)
        try container.encode(sourceID, forKey: .sourceID)
        try container.encode(badge, forKey: .badge)
    }
}

/// 검색 한 번의 전체 결과(빈 배열 대신 상태·메시지 포함).
public struct CapabilitySearchResult: Codable, Equatable, Sendable {
    public let status: CapabilitySearchStatus
    public let message: String
    public let query: String
    public let tokens: [String]
    public let hits: [CapabilitySearchHit]
    public let scannedApps: Int
    public let durationMs: Double
    public let registryPath: String
    public let registryMTime: Double?

    public struct Registry: Sendable, Equatable {
        public var path: String
        public var mTime: Double?

        public init(path: String, mTime: Double?) {
            self.path = path
            self.mTime = mTime
        }
    }

    public init(
        status: CapabilitySearchStatus,
        message: String,
        query: String,
        tokens: [String],
        hits: [CapabilitySearchHit],
        scannedApps: Int,
        durationMs: Double,
        registry: Registry
    ) {
        self.status = status
        self.message = message
        self.query = query
        self.tokens = tokens
        self.hits = hits
        self.scannedApps = scannedApps
        self.durationMs = durationMs
        self.registryPath = registry.path
        self.registryMTime = registry.mTime
    }
}

public typealias ToolCatalogEntry = CapabilitySearcher.ToolCatalogEntry

extension CapabilitySearcher {
    public struct ToolCatalogEntry: Sendable, Equatable {
        public let name: String
        public let kind: ToolKind
        public let sourceID: String
        public let cli: String
        public let version: String
        public let summary: String
        public let commands: [Capabilities.Command]

        public init(
            name: String,
            kind: ToolKind,
            sourceID: String,
            cli: String,
            version: String,
            summary: String,
            commands: [Capabilities.Command] = []
        ) {
            self.name = name
            self.kind = kind
            self.sourceID = sourceID
            self.cli = cli
            self.version = version
            self.summary = summary
            self.commands = commands
        }
    }

    public struct AgentRegistryFilePayload: Codable, Sendable {
        public struct AgentEntry: Codable, Sendable {
            public let id: String
            public let name: String
            public let persona: String?
            public let personaEmoji: String?
            public let agent: String?
            public let model: String?
            public let permissionMode: String?
            public let defaultCwd: String?
            public let skillIDs: [String]?
            public let notes: String?

            public init(
                id: String,
                name: String,
                persona: String? = nil,
                personaEmoji: String? = nil,
                agent: String? = nil,
                model: String? = nil,
                permissionMode: String? = nil,
                defaultCwd: String? = nil,
                skillIDs: [String]? = nil,
                notes: String? = nil
            ) {
                self.id = id
                self.name = name
                self.persona = persona
                self.personaEmoji = personaEmoji
                self.agent = agent
                self.model = model
                self.permissionMode = permissionMode
                self.defaultCwd = defaultCwd
                self.skillIDs = skillIDs
                self.notes = notes
            }
        }
        public let version: Int?
        public let agents: [AgentEntry]

        public init(version: Int? = 1, agents: [AgentEntry]) {
            self.version = version
            self.agents = agents
        }
    }

    public struct HostSkillsRegistryPayload: Codable, Sendable {
        public struct SkillEntry: Codable, Sendable {
            public let name: String
            public let category: String?
            public let kind: String?
            public let version: String?
            public let path: String?
            public let description: String?

            public init(
                name: String,
                category: String? = nil,
                kind: String? = nil,
                version: String? = nil,
                path: String? = nil,
                description: String? = nil
            ) {
                self.name = name
                self.category = category
                self.kind = kind
                self.version = version
                self.path = path
                self.description = description
            }
        }
        public let skills: [SkillEntry]

        public init(skills: [SkillEntry]) {
            self.skills = skills
        }
    }

    public struct SkillLockPayload: Codable, Sendable {
        public struct SkillEntry: Codable, Sendable {
            public let source: String?
            public let skillPath: String?

            public init(source: String? = nil, skillPath: String? = nil) {
                self.source = source
                self.skillPath = skillPath
            }
        }
        public let skills: [String: SkillEntry]

        public init(skills: [String: SkillEntry]) {
            self.skills = skills
        }
    }
}
