import Foundation
import KnowledgeBaseWikiCore
import WikiLedgerKit

// court — 심급. 본체는 `LawCourtService`(이의·개정안·항소심·대법원)와 `LawCourtDocket`(대기 목록).
// 계약: docs/contracts.md "agent-law 명령 (ledger 3)" — `court appeal <id> --reason <r>` · `court propose <id> --scope <s>`
// (개정 본문 표준 입력) · `court hear` · `court decide <건 id> --approve|--reject --testimony <증거 id>` ·
// `court list [--level appellate|supreme]`.
// 근거: docs/business-rules.md "심급제", docs/security.md agent-law 격리 표, 결정 0007.
// 쓰기 하위 명령의 쓰기 게이트는 명령 표면이 먼저 판정하고, 공포는 `LawEnactService` 하나다.

let courtUsage = """
사용법: court appeal <id> --reason <r> [--batch <id>] [모델 기록 옵션] [--json]
       court propose <id> --scope <s> [--batch <id>] [모델 기록 옵션] [--json]   (바꿀 내용 전체를 표준 입력)
       court hear [--json]
       court decide <건 id> --approve|--reject --testimony <증거 id> [--batch <id>] [모델 기록 옵션] [--json]
       court list [--level appellate|supreme] [--json]
"""

public func runCourt(context: LawCommandContext, arguments: [String]) {
    guard arguments.count >= 2 else { usageFail(courtUsage) }
    guard context.isLedgerThree else { usageFail("court 는 ledger 3 원장 전용") }
    let options = LawOptions.parse(
        arguments, skip: 2,
        valued: Set(["--reason", "--scope", "--testimony", "--level", "--batch"]).union(LawOptions.modelOptions),
        flags: ["--json", "-j", "--approve", "--reject"], usage: courtUsage)
    let asJSON = options.has("--json")
    let service = LawCourtService(target: context.lawTarget())
    let batch = options.value("--batch") ?? context.environment["MEMO_LEDGER_BATCH"]

    switch arguments[1] {
    case "appeal":
        guard options.positionals.count == 1, let reason = options.value("--reason") else { usageFail(courtUsage) }
        let id = resolveLawReferences([options.positionals[0]], index: context.scopeIndex())[0]
        let actor = context.actor(explicit: options.modelRecord)
        do {
            printEnacted([try service.appeal(id, reason: reason, actor: actor, batch: batch).id], asJSON: asJSON)
        } catch {
            lawFail(error)
        }
    case "propose":
        guard options.positionals.count == 1, let scope = options.value("--scope") else { usageFail(courtUsage) }
        let id = resolveLawReferences([options.positionals[0]], index: context.scopeIndex())[0]
        let actor = context.actor(explicit: options.modelRecord)
        let content = readStandardInputBody()
        do {
            printEnacted(
                [try service.propose(id, scope: scope, content: content, actor: actor, batch: batch).id], asJSON: asJSON)
        } catch {
            lawFail(error)
        }
    case "hear":
        guard options.positionals.isEmpty else { usageFail(courtUsage) }
        printHearing(service.hear(), asJSON: asJSON)
    case "decide":
        let approve = options.has("--approve")
        guard options.positionals.count == 1, approve != options.has("--reject"),
              let testimonyToken = options.value("--testimony")
        else { usageFail(courtUsage) }
        let ids = resolveLawReferences([options.positionals[0], testimonyToken], index: context.scopeIndex())
        let actor = context.actor(explicit: options.modelRecord)
        do {
            let decision = try service.decide(
                caseID: ids[0], approve: approve, testimony: ids[1], actor: actor, batch: batch)
            for note in decision.notes { FileHandle.standardError.write(Data("\(note)\n".utf8)) }
            printEnacted([decision.ruling.id] + decision.actions, asJSON: asJSON)
        } catch {
            lawFail(error)
        }
    case "list":
        guard options.positionals.isEmpty else { usageFail(courtUsage) }
        var level: LawRulingLevel?
        if let raw = options.value("--level") {
            guard let parsed = LawRulingLevel(rawValue: raw) else { usageFail("--level 은 appellate|supreme\n\(courtUsage)") }
            level = parsed
        }
        printCourtCases(service.docket().cases(level: level), asJSON: asJSON)
    default:
        usageFail(courtUsage)
    }
}

// MARK: - 출력

struct CourtCaseJSON: Encodable {
    let id: String
    let kind: String
    let level: String
    let target: String
    let title: String?
    let filed: String
    let finalAppeal: Bool
    let referredBy: String?
    let noticedAt: String
    let decidableAt: String?

    init(_ item: LawCourtCase) {
        id = item.id
        kind = item.kind.rawValue
        level = item.level.rawValue
        target = item.target
        title = item.title
        filed = LawTime.format(item.filed)
        finalAppeal = item.isFinalAppeal
        referredBy = item.referredBy
        noticedAt = LawTime.format(item.noticedAt)
        decidableAt = item.decidableAt.map(LawTime.format)
    }
}

func printCourtCases(_ cases: [LawCourtCase], asJSON: Bool) {
    if asJSON {
        struct Envelope: Encodable { let ok: Bool; let result: Result }
        struct Result: Encodable { let cases: [CourtCaseJSON] }
        printJSON(Envelope(ok: true, result: Result(cases: cases.map(CourtCaseJSON.init))))
        return
    }
    for item in cases {
        var columns = [item.level.rawValue, String(item.id.prefix(8)), item.isFinalAppeal ? "상고" : item.kind.rawValue,
                       "→\(item.target.prefix(8))", item.title ?? ""]
        if let decidable = item.decidableAt { columns.append("결정 가능 \(LawTime.format(decidable))") }
        print(columns.joined(separator: "\t")) // allow:debug
    }
}

func printHearing(_ report: LawHearingReport, asJSON: Bool) {
    if asJSON {
        struct Entry: Encodable {
            let caseID: String
            let ruling: String?
            let outcome: String?
            let arbiter: String?
            let actions: [String]
            let notes: [String]
            let undecided: String?
        }
        struct Envelope: Encodable { let ok: Bool; let result: Result }
        struct Result: Encodable { let entries: [Entry] }
        printJSON(Envelope(ok: true, result: Result(entries: report.entries.map {
            Entry(caseID: $0.caseID, ruling: $0.ruling?.id, outcome: $0.outcome?.rawValue,
                  arbiter: $0.arbiter.map { "\($0.cli.rawValue):\($0.model)" }, actions: $0.actions, notes: $0.notes,
                  undecided: $0.undecidedReason)
        })))
        return
    }
    for entry in report.entries {
        if let ruling = entry.ruling {
            print(ruling.id) // allow:debug — 공포류 표준 출력은 id 한 줄
            for id in entry.actions { print(id) } // allow:debug
            var line = "\(entry.caseID.prefix(8)) → \(entry.outcome?.rawValue ?? "")"
            if let arbiter = entry.arbiter { line += " (\(arbiter.cli.rawValue):\(arbiter.model))" }
            FileHandle.standardError.write(Data((line + "\n").utf8))
            for note in entry.notes { FileHandle.standardError.write(Data("  \(note)\n".utf8)) }
        } else {
            FileHandle.standardError.write(Data(
                "\(entry.caseID.prefix(8)) 미결정(다음 hear 에 다시): \(entry.undecidedReason ?? "")\n".utf8))
        }
    }
    if report.entries.isEmpty { FileHandle.standardError.write(Data("항소심 대기 건 없음\n".utf8)) }
}
