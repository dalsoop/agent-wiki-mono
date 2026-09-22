import Foundation
import LocalizationKit

/// 자리에 앉는 것. 사람이 아니라 **역량**이다.
///
/// 두 종류를 구분하는 이유는 비용이다. 추론이 필요 없는 일을 일꾼에게 시키면 돈이 새고,
/// 정해진 명령으로 되는 일은 기능이 정확하고 공짜다(Hermes 가 스크립트 잡을 둔 이유와 같다).
public enum Occupant: Codable, Sendable, Equatable {
    /// 추론하는 일꾼 — claude·codex. 시키면 방법을 스스로 찾는다.
    case worker(tool: String, agentRef: String?)
    /// 결정적 기능 — 함대의 앱 CLI. 정해진 일만 정확히 한다.
    case app(cli: String)
    /// 빈자리 — 자리·경로는 유지하고 점유자만 비운 상태(occupy 로 다시 채운다).
    case vacant

    public var label: String {
        switch self {
        case .worker(let tool, let ref): ref.map { "\(tool)·\($0)" } ?? tool
        case .app(let cli): cli
        case .vacant: "(빈자리)"
        }
    }

    public var isWorker: Bool { if case .worker = self { return true }; return false }

    public var isVacant: Bool { if case .vacant = self { return true }; return false }
}

/// 자리가 일하는 곳.
public enum Workspace: Codable, Sendable, Equatable {
    /// 작업 공간 없음 — 조회만 하는 기능 자리(예: `@vault list`).
    case none
    /// 이미 있는 디렉터리.
    case path(String)
    /// 이 자리 전용 worktree. **만들고 거두는 건 AgentDeck 이 한다** — 여기서 git 을 직접 만지지 않는다.
    case worktree(anchor: String, path: String?, branch: String?)

    public var directory: String? {
        switch self {
        case .none: nil
        case .path(let p): p
        case .worktree(_, let p, _): p
        }
    }
}

/// 열쇠 — Agent Vault 의 정체·권한 참조. **원문은 절대 여기 두지 않는다.**
///
/// 부여(`--as-owner`)는 사람만 할 수 있으므로 이 앱은 **검증과 안내**까지만 한다.
public struct Keys: Codable, Sendable, Equatable {
    public var tenant: String
    /// Vault 에 등록된 에이전트 id.
    public var agentID: String
    /// 이 자리가 쓸 자격증명 카드 id/이름.
    public var credentials: [String]

    public init(tenant: String, agentID: String, credentials: [String] = []) {
        self.tenant = tenant
        self.agentID = agentID
        self.credentials = credentials
    }
}

/// Agent Browser 세션 바인딩 — 브라우저는 도구가 아니라 **자리에 붙는 자원**.
///
/// - 소유: 프로필·프로세스는 Agent Browser, 계약 포인터만 이 구조체.
/// - 세션 id 공식: `seat:<handle>` (browserctl `--session` 과 1:1).
/// - claim: `exclusive`(기본, 한 자리 전용) | `shared-read`(읽기 공유·쓰기 주의).
public struct BrowserBinding: Codable, Sendable, Equatable {
    /// browserctl `--session` 값. 보통 `seat:<handle>`.
    public var session: String
    /// 용도 라벨 — nicepay · gujo-admin · nest · …
    public var purpose: String?
    /// `exclusive` | `shared-read`
    public var claim: String
    /// browserctl `--agent` 라벨(없으면 keys.agentID 또는 handle 사용 권장).
    public var agentLabel: String?
    public var boundAt: Date?

    public static let claimExclusive = "exclusive"
    public static let claimSharedRead = "shared-read"

    public init(
        session: String,
        purpose: String? = nil,
        claim: String = claimExclusive,
        agentLabel: String? = nil,
        boundAt: Date? = Date()
    ) {
        self.session = session
        self.purpose = purpose
        self.claim = claim
        self.agentLabel = agentLabel
        self.boundAt = boundAt
    }

    /// 세션 id 공식. handle 의 `@` 는 떼고 소문자를 강제하지 않는다(기존 seat handle 규칙 유지).
    public static func sessionID(forHandle handle: String) -> String {
        let h = handle.trimmingCharacters(in: CharacterSet(charactersIn: "@"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "seat:\(h)"
    }

    public static func make(
        handle: String,
        purpose: String? = nil,
        claim: String = claimExclusive,
        agentLabel: String? = nil
    ) -> BrowserBinding {
        let c = (claim == claimSharedRead) ? claimSharedRead : claimExclusive
        return BrowserBinding(
            session: sessionID(forHandle: handle),
            purpose: purpose?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            claim: c,
            agentLabel: agentLabel?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            boundAt: Date()
        )
    }

    /// 에이전트 조작 시 권장 `--agent` 값.
    public func resolvedAgentLabel(keys: Keys?, handle: String) -> String {
        if let a = agentLabel, !a.isEmpty { return a }
        if let id = keys?.agentID, !id.isEmpty { return id }
        return handle
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

/// 상한. 자리를 만들 때 정해두지 않으면 나중에 아무도 안 정한다.
public struct Limits: Codable, Sendable, Equatable {
    public var dailyUSD: Double?
    public var maxTurns: Int?
    public var forbiddenPaths: [String]
    /// 이 자리가 도는 권한 — `plan`(읽기만) · `acceptEdits` · `bypassPermissions`.
    /// 비워두면 실행 엔진 기본이다. 쓰기를 하는 자리는 **여기에 명시**돼야 한다.
    public var permissionMode: String?
    /// 고정 모델. 비싼 기본 모델로 도는 걸 자리 단위로 막을 수 있다.
    public var model: String?
    /// 등급(AgentTier) — meta·coordinator·worker·verifier.
    ///
    /// 자리는 *어디서·무슨 권한*을, 등급은 *어떤 판단력*을 정한다. 둘이 서로 모르면
    /// 자리마다 모델을 손으로 적어야 한다. 등급을 주면 `AgentTierKit` 정책에서
    /// 모델·effort 가 따라온다(자리에 model 을 직접 쓰면 그게 이긴다).
    public var tier: String?

    public init(
        dailyUSD: Double? = nil, maxTurns: Int? = nil, forbiddenPaths: [String] = [],
        permissionMode: String? = nil, model: String? = nil, tier: String? = nil
    ) {
        self.dailyUSD = dailyUSD
        self.maxTurns = maxTurns
        self.forbiddenPaths = forbiddenPaths
        self.permissionMode = permissionMode
        self.model = model
        self.tier = tier
    }

    public static let none = Limits()
}

/// 자리 — 이 앱의 도메인 객체.
///
/// 자리는 앉는 사람보다 오래 산다. `@reviewer` 라는 자리에 오늘은 claude 가, 내일은 codex 가
/// 앉는다. 그래서 작업 공간·열쇠·상한·대화 맥락·**브라우저 세션**은 **도구가 아니라 자리에** 붙는다.
public struct Seat: Codable, Sendable, Equatable, Identifiable {
    /// `@` 없이 저장한다. 소비자(agent-chat 등)가 `@handle` 을 이걸로 푼다.
    public var handle: String
    public var displayName: String?
    public var occupant: Occupant
    public var workspace: Workspace
    public var keys: Keys?
    public var limits: Limits
    /// Agent Browser 세션 계약. 없으면 브라우저는 이 자리에 안 묶인 것.
    public var browser: BrowserBinding?
    public var hiredAt: Date
    public var note: String?

    public var id: String { handle }

    public init(
        handle: String,
        displayName: String? = nil,
        occupant: Occupant,
        workspace: Workspace = .none,
        keys: Keys? = nil,
        limits: Limits = .none,
        browser: BrowserBinding? = nil,
        hiredAt: Date = Date(),
        note: String? = nil
    ) {
        self.handle = handle
        self.displayName = displayName
        self.occupant = occupant
        self.workspace = workspace
        self.keys = keys
        self.limits = limits
        self.browser = browser
        self.hiredAt = hiredAt
        self.note = note
    }

    /// 해고할 때 **거둘 것이 있나**. 회수를 안 하면 좀비 worktree 가 쌓인다.
    public var hasReclaimableWorkspace: Bool {
        if case .worktree(_, let path, _) = workspace { return path != nil }
        return false
    }

    /// browserctl 에 넘길 세션 id — binding 이 있으면 그 session, 없으면 공식 id.
    public var browserSessionID: String {
        browser?.session ?? BrowserBinding.sessionID(forHandle: handle)
    }
}

/// 고용 가능한 후보 하나 — 함대 앱의 이력서.
///
/// 245개 앱이 이미 `capabilities` 로 같은 양식을 써놨다. 새로 쓰게 하지 않고 그걸 읽는다.
public struct RosterEntry: Codable, Sendable, Equatable, Identifiable {
    public var cli: String
    public var commands: [Command]
    /// `capabilities` 가 응답했나. 없으면 이력서가 없는 것 — 고용 후보에서 뺀다.
    public var responded: Bool
    public var scannedAt: Date

    public var id: String { cli }

    public struct Command: Codable, Sendable, Equatable {
        public var name: String
        public var summary: String
        public init(name: String, summary: String) {
            self.name = name
            self.summary = summary
        }
    }

    public init(cli: String, commands: [Command] = [], responded: Bool, scannedAt: Date = Date()) {
        self.cli = cli
        self.commands = commands
        self.responded = responded
        self.scannedAt = scannedAt
    }

    /// 사람이 읽을 한 줄 — 자리에 앉힐지 고를 때 보는 것.
    public var summaryLine: String {
        guard responded else { return CLILocalization.format("Models.return", cli) }
        let names = commands.prefix(5).map(\.name).joined(separator: ", ")
        return "\(cli)  [\(commands.count)]  \(names)"
    }
}
