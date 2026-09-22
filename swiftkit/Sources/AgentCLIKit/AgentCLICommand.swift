import Foundation
import InteropKit
import AgentScanKit
import AgentCardKit
import AgentRegistryKit
import SkillRegistryKit
import LLMRuntimeKit

/// 각 앱 CLI가 `agent` / `skill` / `chat` / `status` 를 공통 표면으로 갖게 하는 골격.
/// main.swift 에서 `AgentCLICommand(app:).handle(args)` 한 줄로 위임한다.
/// Foundation-only — AppKit/SwiftUI 를 끌지 않는다(dual-entry CLI 타겟 호환).
/// 공용 PATH·레지스트리 진단은 `app-fleet-doctor`. `doctor` 동사는 도메인 extra 가 있는 앱만 직접 둔다.

/// 앱이 자기 도메인 컨텍스트를 주입하는 정보.
public struct AgentCLIApp: Sendable {
    public let slug: String
    public let workspaceRoot: URL?
    /// LLM 프롬프트 머리에 들어갈 앱 도메인 컨텍스트(열린 DB·스키마·최근 작업 등).
    public let domainContext: @Sendable () -> String
    /// 앱이 이미 쓰는 동사. `handle` 이 레일로 가로채지 않는다 (`agent` nvidia-smi 등).
    public let reservedCommands: Set<String>

    public init(slug: String,
                workspaceRoot: URL? = nil,
                domainContext: @escaping @Sendable () -> String = { "" },
                reservedCommands: Set<String> = []) {
        self.slug = slug
        self.workspaceRoot = workspaceRoot
        self.domainContext = domainContext
        self.reservedCommands = reservedCommands
    }
}

/// handle 결과 — 처리했으면 그 exit code 로 종료, 아니면 앱이 기존 로직으로 계속.
public enum AgentCLIExit: Sendable {
    case handled(Int32)
    case notHandled
}

public struct AgentCLICommand: Sendable {
    public let app: AgentCLIApp

    public init(app: AgentCLIApp) { self.app = app }

    /// args[0] 이 `railVerbs` 이면 처리. 예약 동사와 그 외는 .notHandled.
    public func handle(_ args: [String]) async -> AgentCLIExit {
        guard let cmd = args.first else { return .notHandled }
        if app.reservedCommands.contains(cmd) { return .notHandled }
        guard Self.railVerbs.contains(cmd) else { return .notHandled }
        let rest = Array(args.dropFirst())
        switch cmd {
        case "agent": return await runAgent(rest)
        case "skill": return runSkill(rest)
        case "chat": return await runChat(rest)
        case "status": return runStatus(rest)
        default: return .notHandled
        }
    }

    private func runStatus(_ rest: [String]) -> AgentCLIExit {
        let parsed = HelpersDomainCLI.parseJSONFlag(rest[...])
        if let err = parsed.error {
            FileHandle.standardError.write(Data((err + "\n").utf8))
            return .handled(64)
        }
        return .handled(HelpersDomainCLI.status(appKey: app.slug, json: parsed.json))
    }

    // MARK: agent

    private func runAgent(_ args: [String]) async -> AgentCLIExit {
        let sub = args.first ?? "list"
        switch sub {
        case "scan":
            // NSJSONSerialization 은 Swift struct 를 못 다룬다 — [String: Any] 로 평탄화.
            let running: [[String: Any]] = AgentScanner().scan().map { [
                "pid": $0.pid,
                "kind": $0.kind,
                "cwd": $0.cwd,
            ] }
            printEnvelope(["running": running, "cards": cardDicts()])
            return .handled(0)
        case "list":
            printEnvelope(cardDicts().filter { ($0["kind"] as? String) == "agent" })
            return .handled(0)
        case "show":
            let id = args.dropFirst().first
            guard let id else { printEnvelopeError("missing id"); return .handled(64) }
            if let card = cardDicts().first(where: { ($0["id"] as? String) == id }) {
                printEnvelope(card)
                return .handled(0)
            }
            printEnvelopeError("not found: \(id)")
            return .handled(1)
        case "-h", "--help", "help":
            printLines([
                "agent scan          — running agents + this app's agent/skill cards (JSON)",
                "agent list          — declared agents only",
                "agent show <id>     — one card",
            ])
            return .handled(0)
        default:
            printEnvelopeError("unknown agent subcommand: \(sub)")
            return .handled(64)
        }
    }

    // MARK: skill

    private func runSkill(_ args: [String]) -> AgentCLIExit {
        let sub = args.first ?? "list"
        switch sub {
        case "list":
            printEnvelope(cardDicts().filter { ($0["kind"] as? String) == "skill" })
            return .handled(0)
        case "show":
            let id = args.dropFirst().first
            guard let id else { printEnvelopeError("missing id"); return .handled(64) }
            if let card = cardDicts().first(where: { ($0["id"] as? String) == id }) {
                printEnvelope(card)
                return .handled(0)
            }
            printEnvelopeError("not found: \(id)")
            return .handled(1)
        case "-h", "--help", "help":
            printLines([
                "skill list          — skills (workspace .claude/skills + global)",
                "skill show <id>     — one card",
            ])
            return .handled(0)
        default:
            printEnvelopeError("unknown skill subcommand: \(sub)")
            return .handled(64)
        }
    }

    // MARK: chat

    private func runChat(_ args: [String]) async -> AgentCLIExit {
        var backend = "claude"
        var agentID: String?
        var sessionID: String?
        var promptParts: [String] = []
        var i = 0
        while i < args.count {
            switch args[i] {
            case "--backend", "-b":
                guard i + 1 < args.count else { printEnvelopeError("--backend needs value"); return .handled(64) }
                backend = args[i + 1]; i += 2
            case "--agent":
                guard i + 1 < args.count else { printEnvelopeError("--agent needs value"); return .handled(64) }
                agentID = args[i + 1]; i += 2
            case "--resume":
                guard i + 1 < args.count else { printEnvelopeError("--resume needs value"); return .handled(64) }
                sessionID = args[i + 1]; i += 2
            case "-h", "--help":
                printLines([
                    "chat [--backend claude|codex|grok] [--agent <id>] [--resume <sid>] <prompt>",
                    "prompt is joined from remaining args; app domain context is prepended.",
                ])
                return .handled(0)
            default:
                promptParts.append(args[i]); i += 1
            }
        }
        let prompt = promptParts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { printEnvelopeError("missing prompt"); return .handled(64) }

        let def: AgentDef
        if let id = agentID, let found = AgentRegistry().find(id: id) {
            def = found
        } else {
            def = AgentDef(identity: .init(name: "\(app.slug)-chat"), runtime: .init(agent: backend))
        }

        let context = app.domainContext()
        let request = LLMRunRequest(
            prompt: prompt,
            agent: def,
            cwd: app.workspaceRoot?.path,
            sessionID: sessionID,
            contextPreamble: context.isEmpty ? nil : context
        )
        do {
            let result = try await LLMRuntime().run(request)
            printEnvelope([
                "text": result.text,
                "session_id": result.sessionID as Any,
                "is_error": result.isError,
                "num_turns": result.numTurns as Any,
                "cost_usd": result.costUSD as Any,
            ])
            return .handled(result.isError ? 1 : 0)
        } catch {
            printEnvelopeError(String(describing: error))
            return .handled(1)
        }
    }

    // MARK: catalog

    private func catalog() -> AppCardCatalog {
        AppCardCatalog(appSlug: app.slug,
                       workspaceRoot: app.workspaceRoot)
    }

    private func cardDicts() -> [[String: Any]] {
        catalog().cards().map { CardJSON.dict($0) }
    }
}

// MARK: - JSON output helpers (Envelope — CLI 표준 봉투)

struct CardJSON {
    static func dict(_ c: any CatalogCard) -> [String: Any] {
        var d: [String: Any] = [
            "id": c.cardID,
            "title": c.title,
            "kind": c.kind.rawValue,
        ]
        for (k, v) in [("subtitle", c.subtitle), ("tool", c.tool), ("path", c.path), ("summary", c.summary)] {
            if let v { d[k] = v }
        }
        return d
    }
}

func printEnvelope(_ result: Any) {
    guard let data = try? Envelope.okObject(result) else { return }
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
}

func printEnvelopeError(_ message: String) {
    guard let data = try? Envelope.failObject(message) else { return }
    FileHandle.standardError.write(data)
    FileHandle.standardError.write(Data("\n".utf8))
}

func printLines(_ lines: [String]) {
    FileHandle.standardOutput.write(Data((lines.joined(separator: "\n") + "\n").utf8))
}
