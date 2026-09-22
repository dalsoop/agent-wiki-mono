import Foundation

/// AWO(agent-worker-orchestrator) JobSpec 계약의 클라이언트 사본.
///
/// 24개 앱이 각자 `JobSpecPayload`를 재정의하고 있던 것을 하나로 통합한다.
/// 정본은 AWO Core의 `JobSpec`이고, 이 타입은 JSON 직렬화 계약만 맞추는 경량 사본이다.
/// Swift 모듈 의존 없이 CLI JSON 파일로만 결합한다.
public struct AWOJobSpec: Codable, Sendable, Equatable {
    public var title: String
    public var workdir: String
    public var brief: String?
    public var prompt: String?
    public var worker: String
    public var tier: String
    public var model: String?
    public var effort: String
    public var dependsOn: [String]
    public var serializeAfter: [String]
    public var isolation: String
    public var allowedPaths: [String]
    public var forbiddenPaths: [String]
    public var verifyCommand: String?
    public var checkerBrief: String?
    public var timeoutMinutes: Int
    public var backlogIDs: [String]
    public var tenantID: String?

    public struct Routing: Sendable, Equatable {
        public var worker: String
        public var tier: String
        public var effort: String
        public var dependsOn: [String]
        public var serializeAfter: [String]
        public var isolation: String

        public init(
            worker: String = "codex",
            tier: String = "worker",
            effort: String = "medium",
            dependsOn: [String] = [],
            serializeAfter: [String] = [],
            isolation: String = "forbid-worktree"
        ) {
            self.worker = worker
            self.tier = tier
            self.effort = effort
            self.dependsOn = dependsOn
            self.serializeAfter = serializeAfter
            self.isolation = isolation
        }
    }

    public struct Limits: Sendable, Equatable {
        public var allowedPaths: [String]
        public var forbiddenPaths: [String]
        public var verifyCommand: String?
        public var checkerBrief: String?
        public var timeoutMinutes: Int
        public var backlogIDs: [String]

        public init(
            allowedPaths: [String] = [],
            forbiddenPaths: [String] = [],
            verifyCommand: String? = nil,
            checkerBrief: String? = nil,
            timeoutMinutes: Int = 90,
            backlogIDs: [String] = []
        ) {
            self.allowedPaths = allowedPaths
            self.forbiddenPaths = forbiddenPaths
            self.verifyCommand = verifyCommand
            self.checkerBrief = checkerBrief
            self.timeoutMinutes = timeoutMinutes
            self.backlogIDs = backlogIDs
        }
    }

    public init(
        title: String,
        workdir: String,
        prompt: String? = nil,
        brief: String? = nil,
        model: String? = nil,
        routing: Routing = Routing(),
        limits: Limits = Limits(),
        tenantID: String? = "tenant:personal"
    ) {
        self.title = title
        self.workdir = workdir
        self.prompt = prompt
        self.brief = brief
        self.worker = routing.worker
        self.tier = routing.tier
        self.model = model
        self.effort = routing.effort
        self.dependsOn = routing.dependsOn
        self.serializeAfter = routing.serializeAfter
        self.isolation = routing.isolation
        self.allowedPaths = limits.allowedPaths
        self.forbiddenPaths = limits.forbiddenPaths
        self.verifyCommand = limits.verifyCommand
        self.checkerBrief = limits.checkerBrief
        self.timeoutMinutes = limits.timeoutMinutes
        self.backlogIDs = limits.backlogIDs
        self.tenantID = tenantID
    }

    /// 소비 앱이 `worker`·`effort`·`backlogIDs` 를 최상위로 넘기던 시절의 입구.
    /// 정본은 `routing`/`limits` 이고, 이 overload 는 그 필드로만 옮긴다.
    @_disfavoredOverload
    public init(
        title: String,
        workdir: String,
        prompt: String? = nil,
        brief: String? = nil,
        worker: String = "codex",
        model: String? = nil,
        effort: String = "medium",
        backlogIDs: [String] = [],
        tenantID: String? = "tenant:personal"
    ) {
        self.init(
            title: title,
            workdir: workdir,
            prompt: prompt,
            brief: brief,
            model: model,
            routing: Routing(worker: worker, effort: effort),
            limits: Limits(backlogIDs: backlogIDs),
            tenantID: tenantID
        )
    }

    public func writeJSON(to path: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let data = try encoder.encode(self)
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    private enum CodingKeys: String, CodingKey {
        case title, workdir, brief, prompt, worker, tier, model, effort
        case dependsOn, serializeAfter, isolation, allowedPaths, forbiddenPaths
        case verifyCommand, checkerBrief, timeoutMinutes, backlogIDs, tenantID
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decode(String.self, forKey: .title)
        workdir = try c.decode(String.self, forKey: .workdir)
        brief = try c.decodeIfPresent(String.self, forKey: .brief)
        prompt = try c.decodeIfPresent(String.self, forKey: .prompt)
        worker = try c.decodeIfPresent(String.self, forKey: .worker) ?? "codex"
        tier = try c.decodeIfPresent(String.self, forKey: .tier) ?? "worker"
        model = try c.decodeIfPresent(String.self, forKey: .model)
        effort = try c.decodeIfPresent(String.self, forKey: .effort) ?? "medium"
        dependsOn = try c.decodeIfPresent([String].self, forKey: .dependsOn) ?? []
        serializeAfter = try c.decodeIfPresent([String].self, forKey: .serializeAfter) ?? []
        isolation = try c.decodeIfPresent(String.self, forKey: .isolation) ?? "forbid-worktree"
        allowedPaths = try c.decodeIfPresent([String].self, forKey: .allowedPaths) ?? []
        forbiddenPaths = try c.decodeIfPresent([String].self, forKey: .forbiddenPaths) ?? []
        verifyCommand = try c.decodeIfPresent(String.self, forKey: .verifyCommand)
        checkerBrief = try c.decodeIfPresent(String.self, forKey: .checkerBrief)
        timeoutMinutes = try c.decodeIfPresent(Int.self, forKey: .timeoutMinutes) ?? 90
        backlogIDs = try c.decodeIfPresent([String].self, forKey: .backlogIDs) ?? []
        tenantID = try c.decodeIfPresent(String.self, forKey: .tenantID)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(title, forKey: .title)
        try c.encode(workdir, forKey: .workdir)
        try c.encodeIfPresent(brief, forKey: .brief)
        try c.encodeIfPresent(prompt, forKey: .prompt)
        try c.encode(worker, forKey: .worker)
        try c.encode(tier, forKey: .tier)
        try c.encodeIfPresent(model, forKey: .model)
        try c.encode(effort, forKey: .effort)
        if !dependsOn.isEmpty { try c.encode(dependsOn, forKey: .dependsOn) }
        if !serializeAfter.isEmpty { try c.encode(serializeAfter, forKey: .serializeAfter) }
        try c.encode(isolation, forKey: .isolation)
        if !allowedPaths.isEmpty { try c.encode(allowedPaths, forKey: .allowedPaths) }
        if !forbiddenPaths.isEmpty { try c.encode(forbiddenPaths, forKey: .forbiddenPaths) }
        try c.encodeIfPresent(verifyCommand, forKey: .verifyCommand)
        try c.encodeIfPresent(checkerBrief, forKey: .checkerBrief)
        try c.encode(timeoutMinutes, forKey: .timeoutMinutes)
        if !backlogIDs.isEmpty { try c.encode(backlogIDs, forKey: .backlogIDs) }
        try c.encodeIfPresent(tenantID, forKey: .tenantID)
    }
}
