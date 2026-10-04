import Foundation
import KnowledgeBaseWikiCore

// restore <batch> — 원상회복. ledger 3 는 `LawEnactService.restore`, ledger 2 는 옛 rollback.
// 근거: docs/contracts.md "agent-law 명령 (ledger 3)", docs/business-rules.md "공포·개정·폐지·원상회복".

let restoreUsage = "사용법: restore <batch> [모델 기록 옵션] [--json]"

public func runRestore(context: LawCommandContext, arguments: [String]) {
    let options = LawOptions.parse(arguments, valued: LawOptions.modelOptions, usage: restoreUsage)
    guard options.positionals.count == 1 else { usageFail(restoreUsage) }
    let batch = options.positionals[0]
    guard context.isLedgerThree else {
        context.ledgerTwo.checkWritePermission()
        do {
            let store = context.ledgerStore
            let published = try store.rollback(batchID: batch, author: context.author)
            syncIndexAfterWrite(store)
            printEnacted(published.map(\.id), asJSON: options.has("--json"))
        } catch {
            fail("\(error)")
        }
        return
    }
    do {
        let enacted = try LawEnactService.restore(
            batch: batch, actor: context.actor(explicit: options.modelRecord), target: context.lawTarget())
        printEnacted(enacted.map(\.id), asJSON: options.has("--json"))
    } catch {
        lawFail(error)
    }
}
