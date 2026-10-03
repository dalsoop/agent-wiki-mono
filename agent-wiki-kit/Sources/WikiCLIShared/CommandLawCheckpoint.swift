import Foundation
import KnowledgeBaseWikiCore

// checkpoint (ledger 3) — 기록 집합의 수·해시를 적은 체크포인트를 공포한다. ledger 2 는 옛 `runCheckpoint`.
// 근거: docs/contracts.md "agent-law 명령 (ledger 3)"(checkpoint 는 두 형식 모두에서 동작).

public func runLawCheckpoint(context: LawCommandContext, arguments: [String]) {
    let options = LawOptions.parse(arguments, valued: LawOptions.modelOptions, usage: "사용법: checkpoint [--json]")
    guard options.positionals.isEmpty else { usageFail("사용법: checkpoint [--json]") }
    do {
        let stored = try LawEnactService.checkpoint(
            actor: context.actor(explicit: options.modelRecord), target: context.lawTarget())
        printEnacted([stored.id], asJSON: options.has("--json"))
    } catch {
        lawFail(error)
    }
}
