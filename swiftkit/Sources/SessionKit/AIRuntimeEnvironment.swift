import Foundation

/// 실행 도구가 자식 프로세스(셸·훅)에 넘겨주는 환경 변수 이름의 정본.
///
/// 실행 도구별 세션 id·모델·추론 강도·실행 경로 변수 이름은 여기 한 곳에만 둔다
/// (agent-wiki `docs/standards.md` agent-law 절). 확인한 이름만 적는다 — 모르는 도구는 빈 목록이다.
/// - Claude Code: `CLAUDE_CODE_SESSION_ID`·`CLAUDE_EFFORT`·`CLAUDE_CODE_EXECPATH`·`AI_AGENT` (실측 2.1.286).
/// - Codex: `CODEX_THREAD_ID` (codex-cli 0.157.1 실행 파일 문자열에서 확인, 셸 명령 환경에 실림).
extension SupportedAIAgentCLI {
    /// 이 도구가 지금 세션의 id 를 싣는 환경 변수. 앞에 있는 것이 먼저다.
    public var sessionIDEnvironmentKeys: [String] {
        switch self {
        case .claude: ["CLAUDE_CODE_SESSION_ID"]
        case .codex: ["CODEX_THREAD_ID"]
        case .grok, .agy, .opencode, .cursor: []
        }
    }

    /// 정확한 모델 id 를 싣는 환경 변수(별칭이 아닌 것만).
    public var modelEnvironmentKeys: [String] {
        switch self {
        case .claude, .codex, .grok, .agy, .opencode, .cursor: []
        }
    }

    /// 추론 강도를 싣는 환경 변수.
    public var effortEnvironmentKeys: [String] {
        switch self {
        case .claude: ["CLAUDE_EFFORT"]
        case .codex, .grok, .agy, .opencode, .cursor: []
        }
    }

    /// 실행 파일 경로를 싣는 환경 변수. 경로의 마지막 구성 요소가 버전 문자열이다.
    public var versionedExecutablePathEnvironmentKeys: [String] {
        switch self {
        case .claude: ["CLAUDE_CODE_EXECPATH"]
        case .codex, .grok, .agy, .opencode, .cursor: []
        }
    }

    /// `AI_AGENT` 값의 첫 토큰(`<토큰>_<버전>_agent`)으로 쓰는 이름.
    public var aiAgentIdentityToken: String? {
        switch self {
        case .claude: "claude-code"
        case .codex, .grok, .agy, .opencode, .cursor: nil
        }
    }

    /// 실행 도구 식별 환경 변수. 값 예: `claude-code_2-1-286_agent`.
    public static let aiAgentEnvironmentKey = "AI_AGENT"

    /// 환경에 실린 이 도구의 세션 id(공백 제거, 빈 값은 없음).
    public func sessionID(in environment: [String: String]) -> String? {
        Self.firstValue(sessionIDEnvironmentKeys, in: environment)
    }

    /// 세션 id 환경 변수가 실린 첫 도구. 도구 목록 순서로 본다.
    public static func current(in environment: [String: String]) -> SupportedAIAgentCLI? {
        if let identity = aiAgentIdentity(in: environment) { return identity.cli }
        return allCases.first { $0.sessionID(in: environment) != nil }
    }

    /// `AI_AGENT` 를 도구와 버전으로 푼다. 모르는 토큰이면 nil.
    public static func aiAgentIdentity(in environment: [String: String]) -> (cli: SupportedAIAgentCLI, version: String?)? {
        guard let raw = firstValue([aiAgentEnvironmentKey], in: environment) else { return nil }
        let parts = raw.split(separator: "_", omittingEmptySubsequences: false).map(String.init)
        guard let token = parts.first, let cli = allCases.first(where: { $0.aiAgentIdentityToken == token })
        else { return nil }
        var version: String?
        if parts.count > 1 {
            let candidate = parts[1].replacingOccurrences(of: "-", with: ".")
            if candidate.first?.isNumber == true { version = candidate }
        }
        return (cli, version)
    }

    /// 환경에서 읽은 이 도구의 버전. `AI_AGENT` → 실행 경로 마지막 구성 요소 순서.
    public func version(in environment: [String: String]) -> String? {
        if let identity = Self.aiAgentIdentity(in: environment), identity.cli == self, let version = identity.version {
            return version
        }
        guard let path = Self.firstValue(versionedExecutablePathEnvironmentKeys, in: environment) else { return nil }
        let last = (path as NSString).lastPathComponent
        return last.first?.isNumber == true ? last : nil
    }

    /// 환경에서 읽은 이 도구의 모델 id.
    public func model(in environment: [String: String]) -> String? {
        Self.firstValue(modelEnvironmentKeys, in: environment)
    }

    /// 환경에서 읽은 이 도구의 추론 강도.
    public func effort(in environment: [String: String]) -> String? {
        Self.firstValue(effortEnvironmentKeys, in: environment)
    }

    /// 경로에 이 도구의 상태 디렉터리(`~/.claude`·`~/.codex` …)가 들어 있나. 훅 입력의 대화 기록 경로로 도구를 가린다.
    public func ownsPath(_ path: String) -> Bool {
        let components = (path as NSString).standardizingPath.split(separator: "/").map(String.init)
        let needle = defaultStateDirectoryName.split(separator: "/").map(String.init)
        guard !needle.isEmpty, components.count >= needle.count else { return false }
        for start in 0...(components.count - needle.count) where Array(components[start..<start + needle.count]) == needle {
            return true
        }
        return false
    }

    static func firstValue(_ keys: [String], in environment: [String: String]) -> String? {
        for key in keys {
            if let value = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                return value
            }
        }
        return nil
    }
}
