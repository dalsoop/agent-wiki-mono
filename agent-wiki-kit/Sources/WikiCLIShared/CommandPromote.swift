import Foundation
import KnowledgeBaseWikiCore

// promote <id> --to <원장> — ledger 3 승격(영수증 규칙은 옛 승격과 같음, `LawPromotionService`).
// ledger 2 원장의 `promote|promotion preview|publish` 는 각 CLI 의 옛 승격 명령이 그대로 맡는다.
// 근거: docs/contracts.md "agent-law 명령 (ledger 3)"·"승격".

let promoteUsage = "사용법: promote <id> --to <원장> [모델 기록 옵션] [--json]"

public func runLawPromote(context: LawCommandContext, arguments: [String]) {
    let options = LawOptions.parse(
        arguments, valued: Set(["--to"]).union(LawOptions.modelOptions), usage: promoteUsage)
    guard options.positionals.count == 1, let to = options.value("--to") else { usageFail(promoteUsage) }
    let index = context.scopeIndex()
    let sourceID = resolveLawReferences([options.positionals[0]], index: index)[0]
    let source = context.lawTarget()
    guard index.object(id: sourceID)?.world == source.worldName else {
        fail("승격 원본은 현재 원장의 기록이어야 함: \(sourceID)")
    }
    do {
        let result = try LawPromotionService.promote(
            sourceID: sourceID, source: source, targetWorld: to,
            actor: context.actor(explicit: options.modelRecord))
        if options.has("--json") {
            struct Envelope: Encodable { let ok: Bool; let result: LawPromotionResult }
            printJSON(Envelope(ok: true, result: result))
        } else {
            print(result.promotedObjectId) // allow:debug — 공포류 표준 출력은 id 한 줄
            FileHandle.standardError.write(Data((
                "# 원본 영수증 \(result.sourceReceiptObjectId.prefix(8))"
                + (result.targetReceiptObjectId.map { " · 대상 영수증 \($0.prefix(8))" } ?? "")
                + (result.deduplicated ? " · 이미 승격됨" : "") + "\n").utf8))
        }
    } catch {
        lawFail(error)
    }
}
