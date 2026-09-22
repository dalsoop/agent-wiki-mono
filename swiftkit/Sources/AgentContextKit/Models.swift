import Foundation
import AgentSessionKit

/// 한 사실이 **어떻게 알려졌는가**. 이 앱의 모든 출력은 이 태그를 달고 나간다.
///
/// 왜 필수인가 — 런타임마다 로그 충실도가 다르다. Codex 는 주입된 AGENTS.md 원문을
/// rollout jsonl 에 그대로 남기지만, **Claude 는 주입본을 어디에도 남기지 않는다**
/// (세션 jsonl · compaction-snapshot · file-history · backups 전수 확인, 2026-08-04).
/// 그래서 Claude 의 주입 md 는 탐색 규칙으로 **재구성**한 것이지 관측한 게 아니다.
/// 이 구분을 지우면 추측이 사실로 둔갑한다.
public enum Provenance: String, Sendable, Codable, CaseIterable {
    /// 세션 로그에 주입 원문이 그대로 있다. (Codex `session_meta` + AGENTS 블록)
    case injected
    /// 세션이 명시적으로 읽었다. (`Read` tool_use 의 file_path)
    case read
    /// 셸 명령 문자열에서 문서 접근을 발견했다. (`cat`/`sed`/`head`/`grep` …)
    case shell
    /// 탐색 규칙으로 재구성했고, 그 시점 내용까지 스냅샷으로 복원했다.
    case reconstructedExact = "reconstructed-exact"
    /// 탐색 규칙으로 재구성했으나 그 시점 내용은 모른다 — **현재 파일 내용**을 보여준다.
    case reconstructedCurrent = "reconstructed-current"
    /// cwd 상향 walk 밖 레포 정본(예: bare 옆 main/CLAUDE.md). **주입이 아니라 사각.**
    case walkBlindSpot = "walk-blind-spot"

    /// 관측된 사실인가, 규칙으로 유도한 것인가.
    public var isObserved: Bool {
        switch self {
        case .injected, .read, .shell: return true
        case .reconstructedExact, .reconstructedCurrent, .walkBlindSpot: return false
        }
    }
}

/// 세션이 컨텍스트로 받은(또는 받았을) 지침 문서 한 건.
public struct InjectedDoc: Sendable, Codable, Equatable {
    /// 절대 경로. 심링크는 풀지 않은 채 기록한다(에이전트가 본 경로가 그것이므로).
    public let path: String
    /// 탐색 규칙상 어느 층에서 걸렸나. `global` · `workspace` · `repo` · `dir` · `memory` · `import`
    public let layer: String
    public let provenance: Provenance
    /// 파일 크기(바이트). 없으면 nil(경로가 사라진 경우).
    public let bytes: Int?
    /// 대략적 토큰 수. 정확한 토크나이저가 아니라 **추정치**다 — 상대 비교용.
    public let approxTokens: Int?
    /// `@import` 로 끌려온 경우 그것을 끌어온 파일.
    public let importedBy: String?
    /// 파일이 지금 존재하지 않는다(세션 당시엔 있었을 수 있다).
    public let missing: Bool

    public init(
        path: String, layer: String, provenance: Provenance,
        bytes: Int?, approxTokens: Int?, importedBy: String? = nil, missing: Bool = false
    ) {
        self.path = path
        self.layer = layer
        self.provenance = provenance
        self.bytes = bytes
        self.approxTokens = approxTokens
        self.importedBy = importedBy
        self.missing = missing
    }
}

/// 세션이 실제로 손댄 문서 한 건.
public struct TouchedDoc: Sendable, Codable, Equatable {
    public let path: String
    public let provenance: Provenance
    /// 이 세션에서 몇 번 등장했나.
    public let hits: Int
    /// 확장자 기준 문서 종류(`md` · `json` · `txt` …).
    public let kind: String

    public init(path: String, provenance: Provenance, hits: Int, kind: String) {
        self.path = path
        self.provenance = provenance
        self.hits = hits
        self.kind = kind
    }
}

/// 세션 1건의 컨텍스트 카드 — 이 앱의 중심 산출물.
public struct SessionContextCard: Sendable, Codable, Equatable {
    public let tool: String
    public let sessionId: String
    public let cwd: String
    public let title: String?
    public let lastActive: Date
    public let messageCount: Int
    /// 세션 파일을 일부만 읽었나(AgentSessionKit 의 head/tail 창).
    public let truncated: Bool

    /// 주입된(또는 재구성된) 지침 문서 스택. 탐색 순서대로.
    /// 세션 도중 스킬·서브에이전트로 끌려 들어온 md(`skill`·`agent` 층)도 여기 합류한다.
    public let injected: [InjectedDoc]
    /// 실제로 읽거나 건드린 문서.
    public let touched: [TouchedDoc]
    /// 스킬·서브에이전트 활성화를 순서대로 — 무엇을, 왜(직전 사고), 어느 md 로.
    public let activations: [Activation]
    /// 호출된 스킬·슬래시 명령(이름만).
    public let skills: [String]
    /// 스폰된 서브에이전트(이름만).
    public let subagents: [String]
    /// 도구 이름 → 호출 수.
    public let tools: [String: Int]
    /// 주입 스택의 토큰 추정 합계.
    public let injectedApproxTokens: Int
    /// 이 런타임에서 주입본을 관측할 수 있는가. false 면 `injected` 는 전부 재구성이다.
    public let injectionObservable: Bool
    /// 머리 한 줄 요약 — CLI/GUI 최상단.
    public let head: HeadGlance
    /// md 밖 코드·설정 포커스(상위). Bash-heavy 세션에서 문서 섹션이 비어도 여기가 찬다.
    public let codeFocus: [CodeFocus]
    /// walk 밖 레포 정본(예: bare cwd 옆 main/CLAUDE.md). **주입된 게 아니라 사각 후보.**
    public let injectBlindSpots: [InjectedDoc]
    /// 최근 셸 명령 + stdout 첫 줄. "이 문자열을 어디서 읽었나"의 관측 증거.
    public let shellEvidence: [ShellSnippet]

    public struct Identity: Sendable, Equatable {
        public let tool: String
        public let sessionId: String
        public let cwd: String
        public let title: String?
        public let lastActive: Date
        public let messageCount: Int
        public let truncated: Bool

        public init(
            tool: String, sessionId: String, cwd: String, title: String?,
            lastActive: Date, messageCount: Int, truncated: Bool
        ) {
            self.tool = tool
            self.sessionId = sessionId
            self.cwd = cwd
            self.title = title
            self.lastActive = lastActive
            self.messageCount = messageCount
            self.truncated = truncated
        }
    }

    public struct Documents: Sendable, Equatable {
        public let injected: [InjectedDoc]
        public let touched: [TouchedDoc]
        public let activations: [Activation]
        public let skills: [String]
        public let subagents: [String]
        public let tools: [String: Int]

        public init(
            injected: [InjectedDoc], touched: [TouchedDoc], activations: [Activation],
            skills: [String], subagents: [String], tools: [String: Int]
        ) {
            self.injected = injected
            self.touched = touched
            self.activations = activations
            self.skills = skills
            self.subagents = subagents
            self.tools = tools
        }
    }

    public struct Analysis: Sendable, Equatable {
        public let injectedApproxTokens: Int
        public let injectionObservable: Bool
        public let head: HeadGlance
        public let codeFocus: [CodeFocus]
        public let injectBlindSpots: [InjectedDoc]
        public let shellEvidence: [ShellSnippet]

        public init(
            injectedApproxTokens: Int, injectionObservable: Bool,
            head: HeadGlance, codeFocus: [CodeFocus],
            injectBlindSpots: [InjectedDoc] = [],
            shellEvidence: [ShellSnippet] = []
        ) {
            self.injectedApproxTokens = injectedApproxTokens
            self.injectionObservable = injectionObservable
            self.head = head
            self.codeFocus = codeFocus
            self.injectBlindSpots = injectBlindSpots
            self.shellEvidence = shellEvidence
        }
    }

    public init(identity: Identity, documents: Documents, analysis: Analysis) {
        self.activations = documents.activations
        self.tool = identity.tool
        self.sessionId = identity.sessionId
        self.cwd = identity.cwd
        self.title = identity.title
        self.lastActive = identity.lastActive
        self.messageCount = identity.messageCount
        self.truncated = identity.truncated
        self.injected = documents.injected
        self.touched = documents.touched
        self.skills = documents.skills
        self.subagents = documents.subagents
        self.tools = documents.tools
        self.injectedApproxTokens = analysis.injectedApproxTokens
        self.injectionObservable = analysis.injectionObservable
        self.head = analysis.head
        self.codeFocus = analysis.codeFocus
        self.injectBlindSpots = analysis.injectBlindSpots
        self.shellEvidence = analysis.shellEvidence
    }
}

/// 셸 한 줄. stdout 은 첫 줄만 — 전문은 세션 리플레이.
public struct ShellSnippet: Sendable, Codable, Equatable {
    public let command: String
    public let stdoutLine: String?

    public init(command: String, stdoutLine: String? = nil) {
        self.command = command
        self.stdoutLine = stdoutLine
    }
}

/// `search` 한 건 — 세션 id + 어느 필드에서 맞았나.
public struct ShellSearchHit: Sendable, Codable, Equatable {
    public let sessionId: String
    public let tool: String
    public let command: String
    public let stdoutLine: String?
    /// `command` · `stdout` · `user` · `agent` · `recap`
    public let matched: String

    public init(sessionId: String, tool: String, command: String, stdoutLine: String?, matched: String) {
        self.sessionId = sessionId
        self.tool = tool
        self.command = command
        self.stdoutLine = stdoutLine
        self.matched = matched
    }
}

/// `search` 한 페이지 — 0건이 `--limit` 때문인지 구분하려면 `scanned` 가 필요하다.
public struct ShellSearchPage: Sendable, Codable, Equatable {
    public let scanned: Int
    public let hits: [ShellSearchHit]

    public init(scanned: Int, hits: [ShellSearchHit]) {
        self.scanned = scanned
        self.hits = hits
    }
}

/// 목록용 세션 요약(카드 전체를 만들지 않는다 — 빠른 열거용).
public struct SessionSummary: Sendable, Codable, Equatable {
    public let tool: String
    public let sessionId: String
    public let cwd: String
    public let title: String?
    public let lastActive: Date
    public let messageCount: Int
    /// 목록에 찍을 제목 — 최근 user 포커스 우선, 모드 접두 가능.
    public let displayTitle: String
    /// 대략 모드(`bash` · `edit` · `read` · `mixed` · nil).
    public let mode: String?
    /// 최근 사용자 발언 한 줄(있으면).
    public let recentFocus: String?

    public init(_ ref: SessionRef) {
        self.tool = ref.tool.rawValue
        self.sessionId = ref.id
        self.cwd = ref.cwd
        self.title = ref.title
        self.lastActive = ref.lastActive
        self.messageCount = ref.messageCount
        self.displayTitle = ref.title.map { String($0.prefix(72)) } ?? "—"
        self.mode = nil
        self.recentFocus = nil
    }

    public init(
        ref: SessionRef, displayTitle: String, mode: String?, recentFocus: String?
    ) {
        self.tool = ref.tool.rawValue
        self.sessionId = ref.id
        self.cwd = ref.cwd
        self.title = ref.title
        self.lastActive = ref.lastActive
        self.messageCount = ref.messageCount
        self.displayTitle = displayTitle
        self.mode = mode
        self.recentFocus = recentFocus
    }
}

/// 문서 하나를 누가 얼마나 썼나 — 역방향 조회 결과.
public struct DocUsage: Sendable, Codable, Equatable {
    public let path: String
    /// 이 문서를 주입받은 세션 수.
    public let injectedSessions: Int
    /// 이 문서를 실제로 읽은 세션 수.
    public let touchedSessions: Int
    /// walk 밖 사각으로 잡힌 세션 수(주입이 아님).
    public let blindSpotSessions: Int
    /// 관여한 런타임(`claude` · `codex` · `grok`).
    public let tools: [String]
    /// 가장 최근에 이 문서가 걸린 시각.
    public let lastSeen: Date?
    /// 원장이 이 문서를 **처음** 본 시각.
    ///
    /// 왜 필요한가 — "얼마나 쓰이나"는 누적 질문이라 시작점이 있어야 답이 된다.
    /// 세션 로그는 지워지지만 원장은 남으므로, 이 값이 로그보다 오래 산다.
    public let firstSeen: Date?

    public init(
        path: String, injectedSessions: Int, touchedSessions: Int,
        blindSpotSessions: Int = 0, tools: [String], lastSeen: Date?,
        firstSeen: Date? = nil
    ) {
        self.path = path
        self.injectedSessions = injectedSessions
        self.touchedSessions = touchedSessions
        self.blindSpotSessions = blindSpotSessions
        self.tools = tools
        self.lastSeen = lastSeen
        self.firstSeen = firstSeen
    }

    /// 주입·읽힘·사각 모두 없었다 = 죽은 문서.
    public var isDead: Bool {
        injectedSessions == 0 && touchedSessions == 0 && blindSpotSessions == 0
    }

    public var totalSessions: Int {
        injectedSessions + touchedSessions + blindSpotSessions
    }

    /// 마지막으로 걸린 뒤 지난 일수. 원장이 모르면 nil.
    public func daysSinceLastSeen(now: Date = Date()) -> Int? {
        lastSeen.map { max(0, Int(now.timeIntervalSince($0) / 86_400)) }
    }
}

/// `doc` 조회 한 건 — 경로 해석 결과 + 매칭 방식.
public struct DocHit: Sendable, Codable, Equatable {
    public let sessionId: String
    public let tool: String
    public let cwd: String
    public let lastActive: Date
    public let how: Provenance
    public let matchedPath: String

    public init(
        sessionId: String, tool: String, cwd: String, lastActive: Date,
        how: Provenance, matchedPath: String
    ) {
        self.sessionId = sessionId
        self.tool = tool
        self.cwd = cwd
        self.lastActive = lastActive
        self.how = how
        self.matchedPath = matchedPath
    }
}
