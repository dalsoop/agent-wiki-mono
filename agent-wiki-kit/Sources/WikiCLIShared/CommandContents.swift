import Foundation
import KnowledgeBaseWikiCore

// contents — 원장 목차. 지금 원장에서 계산한 목차(열린 경보·대법원 공지·이의 기간 중인 개정안 → 현행 기록)를 낸다.
// 드리밍이 같은 계산으로 목차 기록을 새 판으로 공포하고, 세션 시작 훅은 그 공포된 현행 목차를 보여 준다.
// 계약: docs/contracts.md "agent-law 명령 (ledger 3)" — `contents`. 규칙: docs/business-rules.md "드리밍"(목차).

let contentsUsage = "사용법: contents [--json]"

public func runContents(context: LawCommandContext, arguments: [String]) {
    let options = LawOptions.parse(arguments, valued: [], usage: contentsUsage)
    guard options.positionals.isEmpty else { usageFail(contentsUsage) }
    guard context.isLedgerThree else { usageFail("contents 는 ledger 3 원장 전용") }
    let target = context.lawTarget()
    let maxLines = (context.file.dream ?? LawDreamSettings()).resolvedContentsMaxLines
    let lines = LawContents.lines(for: target, maxLines: maxLines)
    let published = LawContents.current(in: target.store.scan())
    if options.has("--json") {
        struct Result: Encodable { let world: String; let lines: [String]; let published: String? }
        struct Envelope: Encodable { let ok: Bool; let result: Result }
        printJSON(Envelope(ok: true, result: Result(world: target.worldName, lines: lines, published: published?.id)))
        return
    }
    print(LawContents.body(lines), terminator: "") // allow:debug — 명령 결과 출력
}
