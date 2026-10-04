import Foundation
import KnowledgeBaseWikiCore
import WikiLedgerKit

// repeal <id> [--reason <r>] — 폐지. 본문은 이유(비어도 된다). ledger 2 원장은 옛 철회(`retracts`).
// 근거: docs/contracts.md "agent-law 명령 (ledger 3)", docs/business-rules.md "공포·개정·폐지·원상회복".

let repealUsage = "사용법: repeal <id> [--reason <r>] [--batch <id>] [모델 기록 옵션] [--json]"

public func runRepeal(context: LawCommandContext, arguments: [String]) {
    let options = LawOptions.parse(
        arguments, valued: Set(["--reason", "--batch"]).union(LawOptions.modelOptions), usage: repealUsage)
    guard options.positionals.count == 1 else { usageFail(repealUsage) }
    let reason = options.value("--reason") ?? ""
    guard context.isLedgerThree else {
        noteIgnoredModelOptions(options)
        context.ledgerTwo.checkWritePermission()
        let store = context.ledgerStore
        let target = resolve(store, options.positionals[0])
        do {
            let object = try store.publish(
                author: context.author, body: reason,
                extras: LedgerPublishExtras(
                    retracts: target.id, batch: options.value("--batch") ?? context.environment["MEMO_LEDGER_BATCH"]))
            syncIndexAfterWrite(store)
            printEnacted([object.id], asJSON: options.has("--json"))
        } catch {
            fail("\(error)")
        }
        return
    }
    let index = context.scopeIndex()
    let target = resolveLawReferences([options.positionals[0]], index: index)[0]
    let previous = index.object(id: target)
    let draft = LawDraft(
        actor: context.actor(explicit: options.modelRecord),
        title: previous?.object.title.map { "폐지: \($0)" },
        type: previous?.law?.type ?? LawRecordType.record.rawValue,
        batch: options.value("--batch") ?? context.environment["MEMO_LEDGER_BATCH"],
        repeals: target, body: reason)
    let stored = enactLaw(draft, context: context, index: index)
    printEnacted([stored.id], asJSON: options.has("--json"))
}
