import Foundation

/// 코딩 에이전트 CLI 단발 호출 요청 — 스케줄 잡·Gaya·기타 소비자가 공통으로 쓴다.
///
/// **SSOT 경계**
/// - 이 타입 + 어댑터 = *어떻게 부를지* (argv·메타 파서)
/// - 실행(Process)은 CommandKit / LLMRuntimeKit / agent-schedule-dispatcher 가 담당
/// - 스케줄 정본(언제 돌릴지)은 agent-schedule-dispatcher jobs.json
public struct CodingAgentRequest: Sendable, Equatable {
    /// 실행 파일 이름 또는 절대경로 — basename 으로 어댑터 선택.
    public var agent: String
    public var prompt: String
    /// CLI `--model` — nil 이면 해당 CLI 기본 모델.
    public var model: String?
    /// claude/grok 권한 모드 이름 그대로 (acceptEdits|bypassPermissions|plan|…).
    public var permissionMode: String
    public var maxTurns: Int?
    /// 결정적 스크립트 인자 — non-nil 이면 Script 어댑터 (`isScript`).
    public var scriptArgs: [String]?
    /// 강제 스크립트 모드 (빈 scriptArgs 도 허용).
    public var forceScript: Bool

    public var isScript: Bool { forceScript || scriptArgs != nil }

    public init(
        agent: String = "claude",
        prompt: String,
        model: String? = nil,
        permissionMode: String = "acceptEdits",
        maxTurns: Int? = nil,
        scriptArgs: [String]? = nil,
        forceScript: Bool = false
    ) {
        self.agent = agent
        self.prompt = prompt
        self.model = model
        self.permissionMode = permissionMode
        self.maxTurns = maxTurns
        self.scriptArgs = scriptArgs
        self.forceScript = forceScript
    }

    /// basename — `/Users/x/.local/bin/claude` → `claude`.
    public var agentBaseName: String {
        (agent as NSString).lastPathComponent
    }
}

/// 알려진 구독제 코딩 CLI 종류 (확장 포인트).
public enum CodingAgentKind: String, Sendable, CaseIterable {
    case claude
    case codex
    case grok
    case gemini
    case script
    case generic

    public static func resolve(agentBaseName: String, isScript: Bool) -> CodingAgentKind {
        if isScript { return .script }
        switch agentBaseName {
        case "claude": return .claude
        case "codex": return .codex
        case "grok": return .grok
        case "gemini": return .gemini
        default: return .generic
        }
    }
}
