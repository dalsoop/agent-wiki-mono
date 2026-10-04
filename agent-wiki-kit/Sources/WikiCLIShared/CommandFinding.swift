import Foundation
import KnowledgeBaseWikiCore
import WikiLedgerKit

// finding <id> --subject <s> --certainty <c> --domain <d> --reason <r> [--from <t>] [--until <t>]
// 사실인정 — 대상 지식 기록을 `finds` 로 인용하고 본문 머리 칸에 판단 축을 적는다. ledger 3 전용.
// 근거: docs/contracts.md "agent-law 명령 (ledger 3)", docs/business-rules.md "본문 머리 칸"·"사실인정과 4종류".

let findingUsage = """
사용법: finding <id> --subject <person|agent-self|project|external> --certainty <confirmed|probable|possible>
                --domain <분야> --reason <r> [--from <t>] [--until <t>] [--batch <id>] [모델 기록 옵션] [--json]
"""

public func runFinding(context: LawCommandContext, arguments: [String]) {
    let options = LawOptions.parse(
        arguments,
        valued: Set(["--subject", "--certainty", "--domain", "--reason", "--from", "--until", "--batch"])
            .union(LawOptions.modelOptions),
        usage: findingUsage)
    guard options.positionals.count == 1,
          let subject = options.value("--subject"), let certainty = options.value("--certainty"),
          let domain = options.value("--domain"), let reason = options.value("--reason")
    else { usageFail(findingUsage) }
    guard context.isLedgerThree else {
        fail("finding 은 ledger 3 원장 전용 — ledger 2 원장의 분류는 enact 의 --domain --kind --knowledge --classification-reason")
    }
    let index = context.scopeIndex()
    let target = resolveLawReferences([options.positionals[0]], index: index)[0]
    // 머리 칸 순서는 LawHeadFields.keysByType 의 정의 순서를 따른다.
    let values: [String: String?] = [
        "subject": subject, "certainty": certainty, "effective-from": options.value("--from"),
        "effective-until": options.value("--until"), "domain": domain, "reason": reason,
    ]
    let lines = (LawHeadFields.keysByType[.finding] ?? []).compactMap { key -> String? in
        guard let value = values[key] ?? nil else { return nil }
        return "\(key): \(value)"
    }
    let label = index.object(id: target)?.object.title ?? String(target.prefix(8))
    let draft = LawDraft(
        actor: context.actor(explicit: options.modelRecord), title: "사실인정: \(label)",
        type: LawRecordType.finding.rawValue,
        batch: options.value("--batch") ?? context.environment["MEMO_LEDGER_BATCH"],
        cites: [LawCite(id: target, rel: LawRelation.finds.rawValue)],
        body: lines.joined(separator: "\n") + "\n")
    let stored = enactLaw(draft, context: context, index: index, path: .finding)
    printEnacted([stored.id], asJSON: options.has("--json"))
}
