import Foundation

/// 프로세스 역할 분류
public enum ProcessRole: String, Sendable, Equatable {
    case herdr
    case tmux
    case pty
    case claude
    case agy
    case codex
    case grok
    case glm
    case subagent
    case other
}

/// ps 명령 등에서 파싱된 단일 프로세스 기본 레코드
public struct ProcessRecord: Sendable, Equatable, Identifiable {
    public var id: Int32 { pid }
    public let pid: Int32
    public let ppid: Int32
    public let tty: String?
    public let command: String

    public init(pid: Int32, ppid: Int32, tty: String?, command: String) {
        self.pid = pid
        self.ppid = ppid
        self.tty = tty
        self.command = command
    }
}

/// 프로세스 트리 노드 (재귀 트리)
public final class AgentTreeNode: Sendable, Equatable {
    public let pid: Int32
    public let ppid: Int32
    public let command: String
    public let role: ProcessRole
    public let children: [AgentTreeNode]

    public init(pid: Int32, ppid: Int32, command: String, role: ProcessRole, children: [AgentTreeNode] = []) {
        self.pid = pid
        self.ppid = ppid
        self.command = command
        self.role = role
        self.children = children
    }

    public static func == (lhs: AgentTreeNode, rhs: AgentTreeNode) -> Bool {
        lhs.pid == rhs.pid && lhs.role == rhs.role && lhs.children == rhs.children
    }
}

/// 계통 추적 결과: herdr -> tmux -> PTY -> 에이전트 -> 서브에이전트
public struct AgentLineage: Sendable, Equatable {
    public let claudePID: Int32
    public var agentPID: Int32 { claudePID }
    public let ptyPID: Int32?
    public let tmuxPID: Int32?
    public let herdrPID: Int32?
    public let ghosttyPID: Int32?
    public let subagentPIDs: [Int32]

    public init(
        claudePID: Int32,
        ptyPID: Int32? = nil,
        tmuxPID: Int32? = nil,
        herdrPID: Int32? = nil,
        ghosttyPID: Int32? = nil,
        subagentPIDs: [Int32] = []
    ) {
        self.claudePID = claudePID
        self.ptyPID = ptyPID
        self.tmuxPID = tmuxPID
        self.herdrPID = herdrPID
        self.ghosttyPID = ghosttyPID
        self.subagentPIDs = subagentPIDs
    }
}

/// 호스트에서 탐지된 AI 에이전트 프로세스 노드
public struct HostAgentProcess: Sendable, Equatable, Identifiable {
    public var id: Int32 { pid }
    public let pid: Int32
    public let ppid: Int32
    public let tty: String?
    public let tool: String
    public let command: String
    public let arguments: [String]
    public let cwd: String?
    public let isSubagent: Bool
    public let subagents: [HostAgentProcess]
    public let subjobCount: Int
    public let runningSubjobCount: Int
    public let sessionID: String?
    public let title: String?
    public let container: String?
    public let status: String
    public let model: String?

    public init(
        pid: Int32,
        ppid: Int32,
        tty: String?,
        tool: String,
        command: String,
        arguments: [String] = [],
        cwd: String? = nil,
        isSubagent: Bool = false,
        subagents: [HostAgentProcess] = [],
        subjobCount: Int = 0,
        runningSubjobCount: Int = 0,
        sessionID: String? = nil,
        title: String? = nil,
        container: String? = nil,
        status: String = "running",
        model: String? = nil
    ) {
        self.pid = pid
        self.ppid = ppid
        self.tty = tty
        self.tool = tool
        self.command = command
        self.arguments = arguments
        self.cwd = cwd
        self.isSubagent = isSubagent
        self.subagents = subagents
        self.subjobCount = subjobCount
        self.runningSubjobCount = runningSubjobCount
        self.sessionID = sessionID
        self.title = title
        self.container = container
        self.status = status
        self.model = model
    }
}

/// 에이전트 프로세스 트리 스캔 결과
public struct HostAgentTreeScanResult: Sendable, Equatable {
    public let agents: [HostAgentProcess]
    public let lineages: [AgentLineage]
    public let totalAgentCount: Int
    public let ghosttyPID: Int32?
    public let herdrServerPID: Int32?
    public let timestamp: Date

    public init(
        agents: [HostAgentProcess],
        lineages: [AgentLineage] = [],
        totalAgentCount: Int,
        ghosttyPID: Int32?,
        herdrServerPID: Int32?,
        timestamp: Date = Date()
    ) {
        self.agents = agents
        self.lineages = lineages
        self.totalAgentCount = totalAgentCount
        self.ghosttyPID = ghosttyPID
        self.herdrServerPID = herdrServerPID
        self.timestamp = timestamp
    }
}

// MARK: - Herdr JSON Models (Top-Level Structs)

public struct HerdrAgentSession: Decodable, Sendable {
    public var value: String?

    public init(value: String? = nil) {
        self.value = value
    }
}

public struct HerdrPane: Decodable, Sendable {
    public var pane_id: String?
    public var agent: String?
    public var agent_status: String?
    public var cwd: String?
    public var foreground_cwd: String?
    public var terminal_title: String?
    public var terminal_title_stripped: String?
    public var agent_session: HerdrAgentSession?
    public var foreground_process_group_id: Int32?
    public var shell_pid: Int32?
    public var foreground_pids: [Int32]?

    public init(
        pane_id: String? = nil,
        agent: String? = nil,
        agent_status: String? = nil,
        cwd: String? = nil,
        foreground_cwd: String? = nil,
        terminal_title: String? = nil,
        terminal_title_stripped: String? = nil,
        agent_session: HerdrAgentSession? = nil,
        foreground_process_group_id: Int32? = nil,
        shell_pid: Int32? = nil,
        foreground_pids: [Int32]? = nil
    ) {
        self.pane_id = pane_id
        self.agent = agent
        self.agent_status = agent_status
        self.cwd = cwd
        self.foreground_cwd = foreground_cwd
        self.terminal_title = terminal_title
        self.terminal_title_stripped = terminal_title_stripped
        self.agent_session = agent_session
        self.foreground_process_group_id = foreground_process_group_id
        self.shell_pid = shell_pid
        self.foreground_pids = foreground_pids
    }
}

public struct HerdrPanesEnvelope: Decodable, Sendable {
    public var panes: [HerdrPane]?

    public init(panes: [HerdrPane]? = nil) {
        self.panes = panes
    }
}

public struct HerdrPaneResponse: Decodable, Sendable {
    public var result: HerdrPanesEnvelope?

    public init(result: HerdrPanesEnvelope? = nil) {
        self.result = result
    }
}

public struct HerdrProcItem: Decodable, Sendable {
    public var pid: Int32?

    public init(pid: Int32? = nil) {
        self.pid = pid
    }
}

public struct HerdrProcessInfoData: Decodable, Sendable {
    public var foreground_process_group_id: Int32?
    public var shell_pid: Int32?
    public var foreground_processes: [HerdrProcItem]?

    public init(
        foreground_process_group_id: Int32? = nil,
        shell_pid: Int32? = nil,
        foreground_processes: [HerdrProcItem]? = nil
    ) {
        self.foreground_process_group_id = foreground_process_group_id
        self.shell_pid = shell_pid
        self.foreground_processes = foreground_processes
    }
}

public struct HerdrProcessInfoEnvelope: Decodable, Sendable {
    public var process_info: HerdrProcessInfoData?

    public init(process_info: HerdrProcessInfoData? = nil) {
        self.process_info = process_info
    }
}

public struct HerdrProcessInfoResponse: Decodable, Sendable {
    public var result: HerdrProcessInfoEnvelope?

    public init(result: HerdrProcessInfoEnvelope? = nil) {
        self.result = result
    }
}
