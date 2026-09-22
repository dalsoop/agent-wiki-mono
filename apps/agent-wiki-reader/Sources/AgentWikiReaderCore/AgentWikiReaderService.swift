import InteropKit
import LocalizationKit
import Foundation
import CommandKit
import AppPathsKit
import KnowledgeBaseWikiCore

/// 보고용 — `agent-wiki` 의 **읽기 전용** 서브커맨드만 프록시한다.
public struct AgentWikiReaderService: Sendable {
    public static let readOnlyCommands: Set<String> = [
        "help", "version", "list", "show", "search", "context", "path",
        "structure", "history", "cited-by", "verify", "world", "graph",
        "recent", "root", "discuss", "diff", "learn", "rules",
    ]

    /// write / 운영 성격 — Reader 에서 거절
    public static let blockedCommands: Set<String> = [
        "publish", "capture", "classify", "rollback", "checkpoint",
        "promotion", "task", "agent", "batch", "policy", "okf-export",
        "weight", "fleet", "init", "hook",
    ]

    /// blob 읽기 서브커맨드(evidence 영역). put/gc 는 쓰기라 제외.
    public static let readOnlyBlobSubcommands: Set<String> = [
        "get", "info", "refs", "path", "verify", "list", "open",
    ]

    /// event 읽기 서브커맨드(events 영역). start/step/ok/fail/append 는 쓰기라 제외.
    public static let readOnlyEventSubcommands: Set<String> = [
        "tree", "tail", "count",
    ]

    /// graph 읽기 서브커맨드. rebuild 는 파생 그래프를 변경하는 쓰기라 제외.
    public static let readOnlyGraphSubcommands: Set<String> = [
        "status", "timeline", "neighbors", "interpretations",
    ]

    private let runner: CommandRunning
    private let agentWikiPath: String

    public init(
        runner: CommandRunning = ProcessCommandRunner(),
        agentWikiPath: String = HostPlatform.cliBinPath("agent-wiki")
    ) {
        self.runner = runner
        self.agentWikiPath = agentWikiPath
    }

    /// 허용 여부 판정 (테스트·CLI 공용)
    public static func isReadOnlyInvocation(_ args: [String]) -> Bool {
        guard let stripped = droppingLeadingGlobalFlags(args) else { return false }
        guard let first = stripped.first else { return true }
        if isHelpOrVersionFlag(first) { return true }
        if first.hasPrefix("-") { return false }
        if blockedCommands.contains(first) { return false }
        if let nested = nestedReadOnlyVerdict(command: first, rest: Array(stripped.dropFirst())) {
            return nested
        }
        return readOnlyCommands.contains(first)
    }

    /// `nil` 은 `--world`/`--as` 값 누락.
    private static func droppingLeadingGlobalFlags(_ args: [String]) -> [String]? {
        var a = args
        while let f = a.first {
            if f == "--world" || f == "--as" {
                if a.count < 2 { return nil }
                a.removeFirst(2)
                continue
            }
            if f == "--json" || f == "--all" || f == "--fleet" {
                a.removeFirst()
                continue
            }
            break
        }
        return a
    }

    private static func isHelpOrVersionFlag(_ first: String) -> Bool {
        first == "-h" || first == "--help" || first == "-V" || first == "--version"
    }

    private static func nestedReadOnlyVerdict(command: String, rest: [String]) -> Bool? {
        switch command {
        case "graph":
            return readOnlyGraphSubcommands.contains(rest.first ?? "")
        case "blob":
            return readOnlyBlobSubcommands.contains(rest.first ?? "")
        case "event":
            return readOnlyEventSubcommands.contains(rest.first ?? "")
        case "gujo":
            return isReadOnlyGujo(rest)
        case "world":
            let sub = rest.first ?? ""
            return sub == "list" || sub == "use"
        case "fleet":
            let sub = rest.first ?? ""
            return sub == "list" || sub == "doctor" || sub == "scan"
        default:
            return nil
        }
    }

    private static func isReadOnlyGujo(_ rest: [String]) -> Bool {
        let sub = rest.first ?? "status"
        if sub == "status" { return true }
        if sub == "peer" {
            return (rest.dropFirst().first ?? "list") == "list"
        }
        return false
    }

    public func status() async -> String {
        let r = await runner.run(agentWikiPath, ["world", "list"])
        return r.ok ? r.trimmedStdout : "error: agent-wiki world list failed"
    }

    public func worldCatalog(selected: String) -> [WikiWorldListItem] {
        let config = LedgerConfig.load()
        return WikiWorldPresentation.listItems(
            worlds: config.effectiveWorlds,
            selectedName: selected
        )
    }

    public func remoteSharedStatus() async -> String {
        let r = await runner.run(agentWikiPath, ["gujo", "status"])
        return r.ok ? r.trimmedStdout : (r.stderr.isEmpty ? CLILocalization.string("AgentWikiReaderService.label") : r.stderr)
    }

    /// agent-wiki 로 전달. 차단 시 exit-style 메시지.
    public func forward(args: [String]) async -> (stdout: String, stderr: String, exitCode: Int32) {
        guard Self.isReadOnlyInvocation(args) else {
            let msg = "agent-wiki-reader: blocked write/ops command — use agent-wiki-studio or agent-wiki\n"
            return ("", msg, 64)
        }
        let r = await runner.run(agentWikiPath, args)
        return (r.stdout, r.stderr, r.exitCode)
    }

    public func ensureDurableStore() throws {
        try DurableAppLayout.ensureDatabase(at: DurableAppLayout.sqliteURL(slug: "agent-wiki-reader"))
    }
}
