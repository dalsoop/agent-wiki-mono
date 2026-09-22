import Foundation
@_exported import SessionKit

/// 인수인계 원본이 될 수 있는 에이전트 CLI.
///
/// 세 툴 모두 **positional 프롬프트**로 새 세션을 시작할 수 있다는 점이 인수인계의 전제다
/// (`claude "…"` / `codex "…"` / `grok "…"`). 세션 파일 포맷은 서로 전혀 호환되지 않으므로
/// "세션 이식"이 아니라 **팩 증류 → 새 세션 주입**이 정본 경로다.
public typealias AgentTool = SupportedAIAgentCLI

public extension SupportedAIAgentCLI {
    /// 같은 툴로 그대로 재개하는 명령(팩 불필요). 크로스툴이 아닐 때의 지름길.
    func nativeResumeArgs(sessionID: String) -> [String] {
        [executable] + resumeArguments(sessionID: sessionID)
    }

    /// `SessionKit.AIRuntime` 과의 다리 (하위 호환성)
    init?(_ runtime: AIRuntime) {
        self = runtime
    }

    var runtime: AIRuntime { self }
}

/// 발견된 과거 세션 하나. 파싱 전 목록용 메타데이터만 담는다(전문 로드는 지연).
public struct SessionRef: Sendable, Identifiable, Equatable, Codable {
    public let tool: AgentTool
    /// 툴이 부여한 세션 UUID.
    public let id: String
    /// 세션이 돌던 작업 디렉터리.
    public let cwd: String
    /// 목록에 보여줄 제목(grok: session_summary / claude: 첫 프롬프트 / codex: thread_name).
    public let title: String?
    public let lastActive: Date
    /// 파싱 진입점 경로(grok: 세션 디렉터리, claude/codex: jsonl 파일).
    public let path: String

    /// 세션 **원문**을 훑을 파일 경로.
    ///
    /// grok 은 세션이 파일이 아니라 **디렉터리**다(`summary.json`·`updates.jsonl`·…).
    /// 그 사실을 필요한 곳마다 각자 알면 한 군데는 반드시 빠지는데, 실제로 빠졌다 —
    /// 이어받음의 **표식 판정**이 `path`(디렉터리)를 열려다 조용히 실패해서 grok 은
    /// 영원히 "추정" 으로만 잡혔다. 아무도 못 알아챈 이유는 grok 대상 인수인계를
    /// 측정할 수 없었기 때문이다(계정 잔액). 그래서 이 지식은 여기 한 곳에 둔다.
    public var transcriptPath: String {
        switch tool {
        case .grok: return path + "/updates.jsonl"
        case .claude, .codex: return path
        case .agy: return path  // 전사본이 곧 sqlite db 파일이다(conversations/<id>.db).
        case .opencode, .cursor: return path
        }
    }
    /// 대화 길이 추정치. 목록 정렬·"알맹이 있는 세션" 판별에 쓴다.
    public let messageCount: Int

    public init(
        tool: AgentTool,
        id: String,
        cwd: String,
        title: String?,
        lastActive: Date,
        path: String,
        messageCount: Int
    ) {
        self.tool = tool
        self.id = id
        self.cwd = cwd
        self.title = title
        self.lastActive = lastActive
        self.path = path
        self.messageCount = messageCount
    }
}

/// 툴 중립 중간 표현. 각 리더가 이 형태로 뱉고, 팩 빌더는 이것만 본다.
///
/// 세 툴의 원본 포맷(claude jsonl / codex jsonl / grok ACP updates.jsonl)을 여기서 흡수해
/// 증류 로직이 포맷 드리프트에 노출되지 않게 한다.
public struct SessionDigest: Sendable, Equatable {
    public var ref: SessionRef
    /// 사용자 발언(시간순). 시스템 주입 잡음은 리더가 이미 걸러낸 상태여야 한다.
    public var userMessages: [String]
    /// 에이전트 발언(시간순).
    public var agentMessages: [String]
    /// 툴이 스스로 남긴 서사 요약(grok `session_recap` 등). 없을 수 있다.
    public var recaps: [String]
    /// 선언된 목표(grok `goal_updated.objective` 등).
    public var goals: [String]
    /// 마지막 계획 상태. 세션의 소수만 계획 도구를 쓰므로 비어 있는 게 정상이다.
    public var plan: [PlanEntry]
    /// 건드린 파일 경로 → 등장 횟수.
    public var files: [String: Int]
    /// 실행한 셸 명령(시간순, 중복 제거 전).
    public var commands: [String]
    /// 셸 한 줄 + stdout 첫 줄. Grok 은 `tool_call_update.rawOutput` 에서 채운다.
    public var commandOutputs: [CommandOutput]
    /// 마지막 턴의 종료 사유(`cancelled` / `error` / …).
    public var stopReason: String?
    /// 파서가 해석하지 못한 이벤트 종류 → 횟수. **드리프트 감지(P2)의 입력.**
    public var unknownEvents: [String: Int]
    /// 세션 파일을 **일부만** 읽었는가(머리+꼬리 창). 파일 빈도·명령 집계가 최근 구간 기준이
    /// 되므로 화면이 그 사실을 알려야 한다.
    public var truncated: Bool = false

    /// 대화를 **읽은 순서 그대로**. 팩은 증류라 최근 지시 몇 개로 압축되는데, 인수자가
    /// "그때 정확히 뭐라고 했나" 를 봐야 할 때가 있다. 같은 파싱 패스에서 곁가지로 모으므로
    /// 추가 읽기 비용이 없다.
    public var turns: [Turn] = []

    public struct Turn: Sendable, Equatable {
        public enum Speaker: String, Sendable { case user, agent }
        public var speaker: Speaker
        public var text: String

        public init(_ speaker: Speaker, _ text: String) {
            self.speaker = speaker
            self.text = text
        }
    }

    public struct Messages: Sendable, Equatable {
        public var userMessages: [String]
        public var agentMessages: [String]
        public var recaps: [String]
        public var goals: [String]

        public init(
            userMessages: [String] = [],
            agentMessages: [String] = [],
            recaps: [String] = [],
            goals: [String] = []
        ) {
            self.userMessages = userMessages
            self.agentMessages = agentMessages
            self.recaps = recaps
            self.goals = goals
        }
    }

    public struct Work: Sendable, Equatable {
        public var plan: [PlanEntry]
        public var files: [String: Int]
        public var commands: [String]
        public var commandOutputs: [CommandOutput]

        public init(
            plan: [PlanEntry] = [],
            files: [String: Int] = [:],
            commands: [String] = [],
            commandOutputs: [CommandOutput] = []
        ) {
            self.plan = plan
            self.files = files
            self.commands = commands
            self.commandOutputs = commandOutputs
        }
    }

    public init(
        ref: SessionRef,
        messages: Messages = .init(),
        work: Work = .init(),
        stopReason: String? = nil,
        unknownEvents: [String: Int] = [:]
    ) {
        self.ref = ref
        self.userMessages = messages.userMessages
        self.agentMessages = messages.agentMessages
        self.recaps = messages.recaps
        self.goals = messages.goals
        self.plan = work.plan
        self.files = work.files
        self.commands = work.commands
        self.commandOutputs = work.commandOutputs
        self.stopReason = stopReason
        self.unknownEvents = unknownEvents
    }
}

/// 셸 명령과, 있으면 stdout 첫 줄.
public struct CommandOutput: Sendable, Equatable, Codable {
    public var command: String
    public var stdoutLine: String?

    public init(command: String, stdoutLine: String? = nil) {
        self.command = command
        self.stdoutLine = stdoutLine
    }
}

/// 계획 항목 한 줄.
public struct PlanEntry: Sendable, Equatable, Codable {
    public enum Status: String, Sendable, Codable {
        case completed
        case inProgress
        case pending
        case unknown

        /// 팩 마크다운에 찍을 체크박스.
        public var marker: String {
            switch self {
            case .completed:  return "[x]"
            case .inProgress: return "[~]"
            case .pending:    return "[ ]"
            case .unknown:    return "[?]"
            }
        }
    }

    public let content: String
    public let status: Status

    public init(content: String, status: Status) {
        self.content = content
        self.status = status
    }

    /// 툴별 상태 문자열을 흡수한다(grok/claude 모두 snake_case 를 쓴다).
    public static func status(from raw: String?) -> Status {
        switch raw {
        case "completed", "done":         return .completed
        case "in_progress", "inProgress": return .inProgress
        case "pending", "todo":           return .pending
        default:                          return .unknown
        }
    }
}

