import Foundation
import KnowledgeBaseWikiCore

// 명령 표면 분기의 한 자리 — 폐지 이름, 형식별(ledger 2/3) 분기, 쓰기 게이트 적용, 새 명령 연결.
// 두 CLI(전역 `agent-wiki`, repo `agent-wiki-local`)가 같은 함수를 부른다.
// 근거: docs/contracts.md "agent-law 명령 (ledger 3)", 결정 0007.

public enum CommandSurfaceRouting {
    /// 폐지된 이름 → 새 이름 안내. 종료 코드 64, 아무것도 하지 않는다.
    public static let retiredCommands: [String: String] = [
        "publish": "enact",
        "verify": "audit",
        "rollback": "restore <batch>",
        "classify": "finding <id> --subject … --certainty … --domain … --reason …",
        "capture": "exhibit put <파일> 뒤 enact --type evidence --exhibit <sha>",
    ]

    /// `blob` 의 쓰기 하위 명령 → 새 이름.
    public static let retiredBlobSubcommands: [String: String] = [
        "put": "exhibit put <파일>",
        "gc": "redact <sha> --reason <r>",
    ]

    /// ledger 2 원장에서만 동작하는 옛 쓰기 명령 → ledger 3 에서의 안내.
    public static let ledgerTwoOnlyCommands: [String: String] = [
        "discuss": "enact --type record (이의는 court appeal)",
        "learn": "report models",
        "metrics": "report models",
        "review": "court appeal|propose",
        "event": "enact --type evidence / summon",
        "task": "enact",
        "orchestration": "enact",
        "agent": "enact",
        "run": "enact",
        "evolve": "enact",
        "role": "enact",
        "policy": "finding",
        "migrate": "enact",
        "tick": "sync · archive · dream run",
        "distill": "dream run",
        "promotion": "promote <id> --to <원장>",
    ]

    /// 폐지 이름이면 안내 문구. 원장을 열기 전에 판정한다(아무것도 하지 않음).
    public static func retiredGuidance(_ arguments: [String]) -> String? {
        guard let command = arguments.first else { return nil }
        let sub = arguments.dropFirst().first
        if let next = retiredCommands[command] {
            return "'\(command)' 는 폐지됨 — 새 명령: \(next) (결정 0007)"
        }
        if command == "blob", let sub, let next = retiredBlobSubcommands[sub] {
            return "'blob \(sub)' 는 폐지됨 — 새 명령: \(next) (결정 0007)"
        }
        if command == "hook", sub == "authoring" {
            return "'hook authoring' 은 폐지됨 — 새 명령: hook session (결정 0007)"
        }
        return nil
    }

    /// ledger 3 원장에서 옛 쓰기 명령이면 안내 문구.
    public static func ledgerTwoOnlyGuidance(_ arguments: [String], isLedgerThree: Bool) -> String? {
        guard isLedgerThree, let command = arguments.first, let next = ledgerTwoOnlyCommands[command] else {
            return nil
        }
        return "'\(command)' 는 ledger 2 원장 전용 — ledger 3 원장에서는: \(next) (결정 0007)"
    }

    /// 대상 원장에 쓰는 명령인가(쓰기 게이트 `WorldWriteGate` 적용 대상). 두 형식 공통.
    public static func isLedgerWrite(_ arguments: [String]) -> Bool {
        guard let command = arguments.first else { return false }
        let sub = arguments.dropFirst().first ?? ""
        switch command {
        case "enact", "amend", "repeal", "restore", "finding", "checkpoint", "promote", "migrate", "tick", "review":
            return true
        case "exhibit": return sub == "put"
        case "judgment": return sub == "register" || sub == "amend"
        case "redact", "archive": return true
        case "summon": return arguments.contains("--record")
        case "court": return ["appeal", "propose", "hear", "decide"].contains(sub)
        case "dream": return sub == "run" || sub == "resume"
        case "promotion": return sub == "publish" || sub == "repair-receipts"
        case "policy": return sub == "classification-baseline"
        case "event": return ["start", "step", "ok", "fail", "append"].contains(sub)
        case "task", "orchestration": return !["list", "chain", "capsule", "context", ""].contains(sub)
        case "agent": return ["run", "sync", "evolve"].contains(sub) || (sub == "role" && arguments.contains("create"))
        case "run", "evolve": return true
        default: return false
        }
    }

    /// enact 계열(옛 publish 의 자리) — `AGENT_WIKI_WORLD` 잠금을 본다.
    public static func isEnactFamily(_ command: String) -> Bool {
        ["enact", "amend", "repeal", "restore", "finding", "checkpoint", "promote",
         "judgment", "redact", "summon", "court", "dream"].contains(command)
    }
}

/// 원장을 연 뒤 부르는 새 명령 표면. 처리했으면(또는 거부로 끝냈으면) 돌아오지 않거나 true.
/// false 면 호출한 CLI 의 옛 분기(ledger 2 명령)로 계속 간다.
public func runCommandSurface(_ arguments: [String], context: LawCommandContext) -> Bool {
    guard let command = arguments.first else { return false }
    let ledgerThree = context.isLedgerThree
    if let guidance = CommandSurfaceRouting.ledgerTwoOnlyGuidance(arguments, isLedgerThree: ledgerThree) {
        usageFail(guidance)
    }
    if CommandSurfaceRouting.isLedgerWrite(arguments), let world = context.world {
        if CommandSurfaceRouting.isEnactFamily(command),
           let denial = WorldEnvLock.denial(
            environment: context.environment, explicitWorld: context.worldOverride, isWrite: true) {
            fail(denial)
        }
        if let denial = WorldWriteGate.denial(
            targetWorld: world.name, catalog: context.catalog,
            registeredDevices: context.file.devices ?? [], currentDevice: context.file.currentDevice) {
            fail(denial.message)
        }
    }
    switch command {
    // 공포 경로(형식별 저장소로 간다)
    case "enact": runEnact(context: context, arguments: arguments)
    case "amend": runAmend(context: context, arguments: arguments)
    case "repeal": runRepeal(context: context, arguments: arguments)
    case "restore": runRestore(context: context, arguments: arguments)
    case "audit": runAudit(context: context, arguments: arguments)
    case "finding": runFinding(context: context, arguments: arguments)
    case "exhibit": runExhibit(context: context, arguments: arguments)
    case "promote" where ledgerThree: runLawPromote(context: context, arguments: arguments)
    case "checkpoint" where ledgerThree: runLawCheckpoint(context: context, arguments: arguments)
    // 조회(ledger 3)
    case "show" where ledgerThree: runLawShow(context: context, arguments: arguments)
    case "list" where ledgerThree: runLawList(context: context, arguments: arguments)
    case "status" where ledgerThree: runLawStatus(context: context, arguments: arguments)
    case "history" where ledgerThree: runLawHistory(context: context, arguments: arguments)
    case "cited-by" where ledgerThree: runLawCitedBy(context: context, arguments: arguments)
    case "path" where ledgerThree: runLawPath(context: context, arguments: arguments)
    case "search", "context":
        guard ledgerThree else { return false }
        runLawSearchOrContext(context: context, arguments: arguments)
    case "index" where ledgerThree: runLawIndex(context: context, arguments: arguments)
    // agent-law 전용 명령
    case "sync": runSync(context: context, arguments: arguments)
    case "archive": runArchive(context: context, arguments: arguments)
    case "redact": runRedact(context: context, arguments: arguments)
    case "summon": runSummon(context: context, arguments: arguments)
    case "court": runCourt(context: context, arguments: arguments)
    case "dream": runDream(context: context, arguments: arguments)
    case "contents": runContents(context: context, arguments: arguments)
    case "report": runReport(context: context, arguments: arguments)
    case "judgment": runJudgment(context: context, arguments: arguments)
    default: return false
    }
    return true
}

extension CommandSurfaceRouting {
    /// agent-law 명령(docs/contracts.md 표)이 쓰는 옵션. 두 CLI 의 `allowedOptions` 에 모두 있어야 한다
    /// (한쪽만 넣으면 다른 CLI 가 64 로 거부한다 — 시험이 두 main.swift 를 대조한다).
    public static let lawOptions: Set<String> = [
        "--title", "--type", "--tag", "--cite", "--exhibit", "--speaker", "--batch", "--also", "--reason",
        "--subject", "--certainty", "--domain", "--from", "--until", "--session", "--since", "--device",
        "--runtime", "--role", "--query", "--record", "--dry-run", "--scope", "--approve", "--reject",
        "--testimony", "--level", "--repo", "--status", "--path", "--to", "--key", "--root", "--parent",
        "--predecessor", "--model", "--runtime-version", "--effort", "--app", "--app-version", "--json",
        "--endpoint", "--bucket", "--region", "--scheduled",
    ]
}
