import Foundation

/// AgentDeck 상태 미러 JSON의 정본 계약 모델 (내결함성 스키마 탑재)
public struct AgentDeckStateContract: Sendable, Codable, Equatable {
    public struct SessionEntry: Sendable, Codable, Equatable {
        public var pid: Int32
        public var tool: String?
        public var projectName: String?
        public var cwd: String?

        public init(pid: Int32, tool: String? = nil, projectName: String? = nil, cwd: String? = nil) {
            self.pid = pid
            self.tool = tool
            self.projectName = projectName
            self.cwd = cwd
        }
    }

    public var agentCount: Int
    public var sessions: [SessionEntry]

    enum CodingKeys: String, CodingKey {
        case agents
        case sessions
        case panes
    }

    public init(agentCount: Int = 0, sessions: [SessionEntry] = []) {
        self.agentCount = agentCount
        self.sessions = sessions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        do {
            let count = try container.decode(Int.self, forKey: .agents)
            self.agentCount = count
            do {
                self.sessions = try container.decode([SessionEntry].self, forKey: .sessions)
            } catch {
                self.sessions = []
            }
        } catch {
            do {
                let array = try container.decode([SessionEntry].self, forKey: .agents)
                self.sessions = array
                self.agentCount = array.count
            } catch {
                self.agentCount = 0
                self.sessions = []
            }
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(agentCount, forKey: .agents)
        if !sessions.isEmpty {
            try container.encode(sessions, forKey: .sessions)
        }
    }
}

/// AWO 상태 미러 JSON의 정본 계약 모델
public struct AwoStateContract: Sendable, Codable, Equatable {
    public struct JobRaw: Sendable, Codable, Equatable {
        public var id: String
        public var title: String?
        public var state: String?
        public var since: Double?
        public var tenantID: String?
        public var roomID: String?

        public init(
            id: String,
            title: String? = nil,
            state: String? = nil,
            since: Double? = nil,
            tenantID: String? = nil,
            roomID: String? = nil
        ) {
            self.id = id
            self.title = title
            self.state = state
            self.since = since
            self.tenantID = tenantID
            self.roomID = roomID
        }
    }

    public struct InnerState: Sendable, Codable, Equatable {
        public var activeJobCount: Int?
        public var generatedAt: Double?
        public var jobs: [JobRaw]?

        public init(activeJobCount: Int? = nil, generatedAt: Double? = nil, jobs: [JobRaw]? = nil) {
            self.activeJobCount = activeJobCount
            self.generatedAt = generatedAt
            self.jobs = jobs
        }
    }

    public var state: InnerState?
    public var jobs: [JobRaw]?

    public init(state: InnerState? = nil, jobs: [JobRaw]? = nil) {
        self.state = state
        self.jobs = jobs
    }

    public var allJobs: [JobRaw] {
        state?.jobs ?? jobs ?? []
    }
}
