import Foundation
import StateRootKit

/// 함대 전체에 걸리는 정책 — **한 곳에서 전부 멈추고, 하루 총액을 막는다.**
///
/// 지금까지 상한은 앱마다 흩어져 있었다. Hermes 는 `paused` 파일로 자기 잡만 멈추고,
/// agent-chat 은 자리별 하루 상한만 보고, agent-worker-orchestrator 는 자기 큐만 안다.
/// 사고가 나면 손이 여러 군데로 가야 했고, "오늘 함대가 얼마 썼나"를 물을 데가 없었다.
///
/// 이 Kit 은 **읽기 계약**이다 — 정책 파일을 해석하고 판정만 한다. 집행(실제로 실행을
/// 안 하는 것)은 각 소비자의 몫이고, 편집은 사람 또는 소유 앱이 한다.
///
///     ~/.agent-policy/policy.json   정책
///     ~/.agent-policy/paused        있으면 전체 정지 (파일이라 재기동을 넘어 durable)
public struct AgentPolicy: Codable, Sendable, Equatable {
    /// 함대 하루 총액(USD). nil 이면 무제한.
    public var dailyUSD: Double?
    /// 동시에 돌 수 있는 에이전트 수. nil 이면 무제한.
    public var maxConcurrent: Int?
    /// 이 경로들은 어떤 자리도 건드리면 안 된다(소비자가 전달·검사).
    public var forbiddenPaths: [String]
    /// 사람이 읽을 메모 — 왜 이렇게 걸었나.
    public var note: String?
    /// 도구 호출 정책. nil 이면 검색 루트를 막지 않는다(옛 policy.json 호환).
    public var tool: AgentToolPolicy?

    public init(
        dailyUSD: Double? = nil,
        maxConcurrent: Int? = nil,
        forbiddenPaths: [String] = [],
        note: String? = nil,
        tool: AgentToolPolicy? = nil
    ) {
        self.dailyUSD = dailyUSD
        self.maxConcurrent = maxConcurrent
        self.forbiddenPaths = forbiddenPaths
        self.note = note
        self.tool = tool
    }

    public static let unrestricted = AgentPolicy()
}

/// 에이전트 도구 호출 정책. 훅 정규식의 정본이 아니라 이 구조체가 정본이다.
public struct AgentToolPolicy: Codable, Sendable, Equatable {
    /// HOME 디렉터리 자체를 find/rg/grep 루트로 쓰지 못하게 한다.
    public var denyHomeRootSearch: Bool
    /// 한 명령에 이 상대 경로가 몇 개 이상이면 세션 사냥으로 본다.
    public var sessionHuntRoots: [String]
    public var sessionHuntMinRoots: Int

    public init(
        denyHomeRootSearch: Bool = true,
        sessionHuntRoots: [String] = [".codex", ".claude", ".grok", ".agy", ".ssot"],
        sessionHuntMinRoots: Int = 3
    ) {
        self.denyHomeRootSearch = denyHomeRootSearch
        self.sessionHuntRoots = sessionHuntRoots
        self.sessionHuntMinRoots = sessionHuntMinRoots
    }

    public static let `default` = AgentToolPolicy()
}

/// 하네스가 넘기는 도구 호출. 명령 문자열 + grep path.
public struct AgentToolCall: Sendable, Equatable {
    public var command: String
    public var path: String

    public init(command: String, path: String = "") {
        self.command = command
        self.path = path
    }
}

/// 정책 저장소 + 판정.
public struct AgentPolicyStore: Sendable {
    public let root: URL

    /// `AGENT_POLICY_HOME` 으로 위치를 바꾼다 — `NSHomeDirectory()` 가 `HOME` 을 무시하므로
    /// 격리 실행·테스트에는 이 변수가 유일한 경로다.
    public init(root: URL? = nil) {
        if let root {
            self.root = root
        } else if let override = ProcessInfo.processInfo.environment["AGENT_POLICY_HOME"],
                  !override.isEmpty {
            self.root = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            self.root = StateRootKit.url(for: ".agent-policy")
        }
    }

    public var policyURL: URL { root.appendingPathComponent("policy.json") }
    /// 존재하면 전체 정지. 파일이라 프로세스·재기동을 넘어 유지된다 — 사고 때의 하드 스톱.
    public var pausedURL: URL { root.appendingPathComponent("paused") }

    // MARK: - 정지

    public var isPaused: Bool { FileManager.default.fileExists(atPath: pausedURL.path) }

    /// 왜 멈췄나 — 없으면 빈 문자열.
    public var pauseReason: String {
        (try? String(contentsOf: pausedURL, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    public func setPaused(_ paused: Bool, reason: String = "") throws {
        if paused {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try Data(reason.utf8).write(to: pausedURL, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: pausedURL)
        }
    }

    // MARK: - 정책

    public func load() -> AgentPolicy {
        guard let data = try? Data(contentsOf: policyURL) else {
            return .unrestricted
        }
        do {
            return try JSONDecoder().decode(AgentPolicy.self, from: data)
        } catch {
            return .unrestricted
        }
    }

    public func save(_ policy: AgentPolicy) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(policy).write(to: policyURL, options: .atomic)
    }

    // MARK: - 판정

    /// 지금 새 실행을 시작해도 되나. 막히면 사람이 읽을 이유를 준다.
    ///
    /// 비용은 실행 **후에야** 알 수 있으므로 총액 상한은 사후 차단기다 — 한 번의 호출이
    /// 상한을 넘길 수 있고, 그 폭은 모델·턴 상한으로만 줄인다. 그래도 다음 호출은 막는다.
    public func verdict(spentTodayUSD: Double, running: Int = 0) -> Verdict {
        if isPaused {
            let reason = pauseReason
            return .blocked("함대 정지 중" + (reason.isEmpty ? "" : " — \(reason)"))
        }
        let policy = load()
        if let cap = policy.dailyUSD, spentTodayUSD >= cap {
            return .blocked(String(format: "오늘 함대 총액을 다 썼다 ($%.4f / $%.2f)", spentTodayUSD, cap))
        }
        if let limit = policy.maxConcurrent, running >= limit {
            return .blocked("동시 실행 상한 \(limit)개에 걸렸다 — 끝나면 다시 시도한다")
        }
        return .allowed
    }

    /// 도구 호출이 정책에 걸리는지. `tool` 칸이 없으면 허용(옛 파일).
    public func toolVerdict(_ call: AgentToolCall) -> Verdict {
        let policy = load()
        guard let tool = policy.tool else { return .allowed }
        let home = (ProcessInfo.processInfo.environment["HOME"] ?? StateRootKit.path(""))
            as NSString
        return tool.verdict(for: call, home: home.standardizingPath)
    }

    public enum Verdict: Sendable, Equatable {
        case allowed
        case blocked(String)

        public var isAllowed: Bool { self == .allowed }
        public var reason: String? {
            if case .blocked(let why) = self { return why }
            return nil
        }
    }
}

extension AgentToolPolicy {
    /// 검색 루트 판정. 소유 CLI 호출은 여기서 막지 않는다.
    public func verdict(for call: AgentToolCall, home: String) -> AgentPolicyStore.Verdict {
        let homeAbs = (home as NSString).standardizingPath
        let cmd = call.command
        let pathIsHome = isHomeRoot(call.path, home: homeAbs)
        let cmdIsHomeSearch = isHomeRootFindOrGrep(cmd, home: homeAbs)
        let homeHit = [pathIsHome, cmdIsHomeSearch].contains(true)
        let hitsHomeRoot = denyHomeRootSearch && homeHit
        guard !hitsHomeRoot else {
            return .blocked("HOME 루트 검색 금지 — 소유 CLI로 조회하세요")
        }
        let minRoots = max(sessionHuntMinRoots, 1)
        let hits = sessionHuntRoots.filter { root in
            let rel = root.hasPrefix(".") ? root : "." + root
            return cmd.contains(homeAbs + "/" + rel) || cmd.contains("$HOME/" + rel)
        }
        guard hits.count < minRoots || !isSearchCommand(cmd) else {
            return .blocked("세션 디렉터리 동시 훑기 금지 — 소유 CLI로 조회하세요")
        }
        return .allowed
    }

    private func isSearchCommand(_ cmd: String) -> Bool {
        cmd.range(of: #"\b(find|rg|grep)\b"#, options: .regularExpression) != nil
    }

    private func isHomeRoot(_ path: String, home: String) -> Bool {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
        if trimmed.isEmpty { return false }
        if trimmed == "~" || trimmed == "$HOME" { return true }
        let expanded = (trimmed as NSString).expandingTildeInPath
        return (expanded as NSString).standardizingPath == (home as NSString).standardizingPath
    }

    private func isHomeRootFindOrGrep(_ cmd: String, home: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: home)
        let findPat = "\\bfind\\s+(?:\\$HOME\\b|~(?=/|\\s|$)|" + escaped + ")(?!/)"
        let grepPat = "\\b(?:rg|grep)\\s+[^\\n]*\\s(?:\\$HOME\\b|~(?=\\s|$)|" + escaped + ")(?!/)"
        if cmd.range(of: findPat, options: .regularExpression) != nil { return true }
        if cmd.range(of: grepPat, options: .regularExpression) != nil { return true }
        return false
    }
}
