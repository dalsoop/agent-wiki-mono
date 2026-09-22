import Foundation

public struct LoopDiagnostic: Codable, Equatable, Sendable {
    public enum Severity: String, Codable, Sendable { case warning, error }
    public var severity: Severity
    public var path: String
    public var message: String

    public init(severity: Severity, path: String, message: String) {
        self.severity = severity
        self.path = path
        self.message = message
    }
}

public struct LoopRosterEntry: Codable, Equatable, Identifiable, Sendable {
    public var role: String
    public var does: String
    public var reads: [String]
    public var writes: [String]
    public var powers: [String]
    public var id: String { role }

    public init(
        role: String,
        does: String,
        reads: [String] = [],
        writes: [String] = [],
        powers: [String] = []
    ) {
        self.role = role
        self.does = does
        self.reads = reads
        self.writes = writes
        self.powers = powers
    }

    private enum CodingKeys: String, CodingKey { case role, does, reads, writes, powers }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        role = try c.decode(String.self, forKey: .role)
        does = try c.decodeIfPresent(String.self, forKey: .does) ?? ""
        reads = try c.decodeIfPresent([String].self, forKey: .reads) ?? []
        writes = try c.decodeIfPresent([String].self, forKey: .writes) ?? []
        powers = try c.decodeIfPresent([String].self, forKey: .powers) ?? []
    }
}

public struct LoopDefinition: Codable, Equatable, Sendable {
    public var id: String
    public var goal: String
    public var rubricDoc: String?
    public var planDoc: String?
    public var repo: String?
    public var branch: String?
    public var gate: Double?
    public var perAxisGate: Double?
    public var maxRounds: Int?
    public var runner: String?
    public var runnerRef: String?
    public var createdAt: String?
    public var roster: [LoopRosterEntry]
    public var note: String?

    public struct Scope: Sendable, Equatable {
        public var rubricDoc: String?
        public var planDoc: String?
        public var repo: String?
        public var branch: String?

        public init(
            rubricDoc: String? = nil,
            planDoc: String? = nil,
            repo: String? = nil,
            branch: String? = nil
        ) {
            self.rubricDoc = rubricDoc
            self.planDoc = planDoc
            self.repo = repo
            self.branch = branch
        }
    }

    public struct Run: Sendable, Equatable {
        public var gate: Double?
        public var perAxisGate: Double?
        public var maxRounds: Int?
        public var runner: String?
        public var runnerRef: String?
        public var createdAt: String?
        public var note: String?

        public init(
            gate: Double? = nil,
            perAxisGate: Double? = nil,
            maxRounds: Int? = nil,
            runner: String? = nil,
            runnerRef: String? = nil,
            createdAt: String? = nil,
            note: String? = nil
        ) {
            self.gate = gate
            self.perAxisGate = perAxisGate
            self.maxRounds = maxRounds
            self.runner = runner
            self.runnerRef = runnerRef
            self.createdAt = createdAt
            self.note = note
        }
    }

    public init(
        id: String,
        goal: String,
        scope: Scope = Scope(),
        run: Run = Run(),
        roster: [LoopRosterEntry] = []
    ) {
        self.id = id
        self.goal = goal
        self.rubricDoc = scope.rubricDoc
        self.planDoc = scope.planDoc
        self.repo = scope.repo
        self.branch = scope.branch
        self.gate = run.gate
        self.perAxisGate = run.perAxisGate
        self.maxRounds = run.maxRounds
        self.runner = run.runner
        self.runnerRef = run.runnerRef
        self.createdAt = run.createdAt
        self.roster = roster
        self.note = run.note
    }

    private enum CodingKeys: String, CodingKey {
        case id, goal, rubricDoc, planDoc, repo, branch, gate, perAxisGate, maxRounds
        case runner, runnerRef, createdAt, roster, note
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        goal = try c.decodeIfPresent(String.self, forKey: .goal) ?? ""
        rubricDoc = try c.decodeIfPresent(String.self, forKey: .rubricDoc)
        planDoc = try c.decodeIfPresent(String.self, forKey: .planDoc)
        repo = try c.decodeIfPresent(String.self, forKey: .repo)
        branch = try c.decodeIfPresent(String.self, forKey: .branch)
        gate = try c.decodeIfPresent(Double.self, forKey: .gate)
        perAxisGate = try c.decodeIfPresent(Double.self, forKey: .perAxisGate)
        maxRounds = try c.decodeIfPresent(Int.self, forKey: .maxRounds)
        runner = try c.decodeIfPresent(String.self, forKey: .runner)
        runnerRef = try c.decodeIfPresent(String.self, forKey: .runnerRef)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        roster = try c.decodeIfPresent([LoopRosterEntry].self, forKey: .roster) ?? []
        note = try c.decodeIfPresent(String.self, forKey: .note)
    }
}

public struct LoopState: Codable, Equatable, Sendable {
    public var status: String?
    public var currentRound: Int?
    public var currentPhase: String?
    public var lastScore: Double?
    public var bestScore: Double?
    public var updatedAt: String?

    public init(
        status: String? = nil,
        currentRound: Int? = nil,
        currentPhase: String? = nil,
        lastScore: Double? = nil,
        bestScore: Double? = nil,
        updatedAt: String? = nil
    ) {
        self.status = status
        self.currentRound = currentRound
        self.currentPhase = currentPhase
        self.lastScore = lastScore
        self.bestScore = bestScore
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case status, currentRound, round, currentPhase, lastScore, bestScore, best, updatedAt
    }

    private struct LegacyBest: Codable { var score: Double? }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = try c.decodeIfPresent(String.self, forKey: .status)
        currentRound = try c.decodeIfPresent(Int.self, forKey: .currentRound)
            ?? c.decodeIfPresent(Int.self, forKey: .round)
        currentPhase = try c.decodeIfPresent(String.self, forKey: .currentPhase)
        lastScore = try c.decodeIfPresent(Double.self, forKey: .lastScore)
        bestScore = try c.decodeIfPresent(Double.self, forKey: .bestScore)
            ?? c.decodeIfPresent(LegacyBest.self, forKey: .best)?.score
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(status, forKey: .status)
        try c.encodeIfPresent(currentRound, forKey: .currentRound)
        try c.encodeIfPresent(currentPhase, forKey: .currentPhase)
        try c.encodeIfPresent(lastScore, forKey: .lastScore)
        try c.encodeIfPresent(bestScore, forKey: .bestScore)
        try c.encodeIfPresent(updatedAt, forKey: .updatedAt)
    }
}

public struct LoopScoreItem: Codable, Equatable, Identifiable, Sendable {
    public var name: String
    public var value: Double
    public var id: String { name }
}

public struct LoopRound: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var round: String?
    public var phase: String
    public var role: String?
    public var agent: String?
    public var status: String?
    public var score: Double?
    public var blockers: [String]
    public var note: String?
    public var evidencePath: String?
    public var target: [String]
    public var rubricAxis: String?
    public var scorecard: [LoopScoreItem]
    public var reads: [String]
    public var filesChanged: [String]
    public var startedAt: String?
    public var endedAt: String?
}

public struct LoopFeedbackEntry: Codable, Equatable, Identifiable, Sendable {
    public var artifact: String
    public var verdict: String
    public var comment: String
    public var by: String
    public var at: String
    public var id: String { "\(at)|\(artifact)|\(verdict)" }

    public init(artifact: String, verdict: String, comment: String, by: String, at: String) {
        self.artifact = artifact
        self.verdict = verdict
        self.comment = comment
        self.by = by
        self.at = at
    }
}

public struct LoopReleaseItem: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var label: String
    public var owner: String
    public var artifact: String
    public var gate: String?

    public var isRequired: Bool { (gate ?? "required") == "required" }
    public var expandedArtifact: String { (artifact as NSString).expandingTildeInPath }
    public var isDone: Bool { FileManager.default.fileExists(atPath: expandedArtifact) }
}

public struct LoopReleaseChecklist: Codable, Equatable, Sendable {
    public var app: String
    public var items: [LoopReleaseItem]

    public var requiredItems: [LoopReleaseItem] { items.filter(\.isRequired) }
    public var requiredDone: Int { requiredItems.filter(\.isDone).count }
    public var isReady: Bool { !requiredItems.isEmpty && requiredDone == requiredItems.count }
}

public struct LoopNode: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var path: String
    public var name: String
    public var isLoop: Bool
    public var isRelease: Bool
    public var children: [LoopNode]
    public var rel: String { id }
}

public struct LoopDetail: Codable, Equatable, Identifiable, Sendable {
    public var id: String { node.id }
    public var node: LoopNode
    public var definition: LoopDefinition?
    public var state: LoopState?
    public var rounds: [LoopRound]
    public var feedback: [LoopFeedbackEntry]
    public var release: LoopReleaseChecklist?
    public var diagnostics: [LoopDiagnostic]

    public var blockerCount: Int {
        rounds.last(where: { !$0.blockers.isEmpty })?.blockers.count ?? 0
    }
}

extension LoopDetail {
    private enum CodingKeys: String, CodingKey {
        case id, node, definition, state, rounds, feedback, release, diagnostics
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        node = try c.decode(LoopNode.self, forKey: .node)
        definition = try c.decodeIfPresent(LoopDefinition.self, forKey: .definition)
        state = try c.decodeIfPresent(LoopState.self, forKey: .state)
        rounds = try c.decodeIfPresent([LoopRound].self, forKey: .rounds) ?? []
        feedback = try c.decodeIfPresent([LoopFeedbackEntry].self, forKey: .feedback) ?? []
        release = try c.decodeIfPresent(LoopReleaseChecklist.self, forKey: .release)
        diagnostics = try c.decodeIfPresent([LoopDiagnostic].self, forKey: .diagnostics) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(node, forKey: .node)
        try c.encodeIfPresent(definition, forKey: .definition)
        try c.encodeIfPresent(state, forKey: .state)
        try c.encode(rounds, forKey: .rounds)
        try c.encode(feedback, forKey: .feedback)
        try c.encodeIfPresent(release, forKey: .release)
        try c.encode(diagnostics, forKey: .diagnostics)
    }
}

public struct LoopProjectSummary: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var loopCount: Int
    public var runningCount: Int
    public var blockedCount: Int
    public var convergedCount: Int
    public var rollupStatus: String
}

public struct LoopLedgerSnapshot: Codable, Equatable, Sendable {
    public var root: String
    public var nodes: [LoopNode]
    public var loops: [LoopDetail]
    public var projects: [LoopProjectSummary]
    public var diagnostics: [LoopDiagnostic]

    public func detail(id: String) -> LoopDetail? {
        loops.first { $0.id == id }
    }
}
