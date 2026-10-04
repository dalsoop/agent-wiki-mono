import Foundation
import KnowledgeBaseWikiCore

// redact <R2 키 또는 sha> --reason <r> — 증거물 가림. 본체는 `LawRedactService.redact`.
// 계약: docs/contracts.md "agent-law 명령 (ledger 3)". 규칙: docs/security.md "R2 와 세션", docs/business-rules.md "본문 머리 칸".
// 원장 기록은 가리지 않는다(거부, 폐지는 repeal). 공포류라 표준 출력에 가림 기록 id 한 줄.

let redactUsage = "사용법: redact <R2 키 또는 sha> --reason <r> [모델 기록 옵션] [--json]"

public func runRedact(context: LawCommandContext, arguments: [String]) {
    let options = LawOptions.parse(
        arguments, valued: Set(["--reason"]).union(LawOptions.modelOptions), usage: redactUsage)
    guard options.positionals.count == 1,
          let reason = options.value("--reason"), !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { usageFail(redactUsage) }
    guard context.isLedgerThree else { usageFail("redact 는 ledger 3 원장 전용") }
    let objectStore: LawR2Client
    do {
        objectStore = try LawR2Client.standard(file: context.file)
    } catch {
        fail("\(error)")
    }
    do {
        let outcome = try LawRedactService.redact(
            options.positionals[0], reason: reason, actor: context.actor(explicit: options.modelRecord),
            target: context.lawTarget(), objectStore: objectStore)
        if options.has("--json") {
            struct Envelope: Encodable { let ok: Bool; let result: LawRedactOutcome }
            printJSON(Envelope(ok: true, result: outcome))
        } else {
            printEnacted([outcome.recordID], asJSON: false)
        }
    } catch {
        lawFail(error)
    }
}
