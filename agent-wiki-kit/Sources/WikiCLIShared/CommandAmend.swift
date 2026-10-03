import Foundation
import KnowledgeBaseWikiCore
import WikiLedgerKit

// amend <id> [--also <id>]… --title <t> … — 개정(본문 표준 입력). `--also` 는 병합 개정(`amends-also`).
// 근거: docs/contracts.md "agent-law 명령 (ledger 3)", docs/business-rules.md "공포·개정·폐지·원상회복".

let amendUsage = """
사용법: amend <id> [--also <id>]… --title <t> [--type <유형>] [--tag <t>]… [--cite <id>[:<rel>]]…
              [--exhibit <sha>]… [--speaker <s>] [--batch <id>] [모델 기록 옵션] [--json]   (본문 표준 입력)
"""

public func runAmend(context: LawCommandContext, arguments: [String]) {
    let options = LawOptions.parse(
        arguments, valued: enactValueOptions.union(["--also"]).union(
            context.isLedgerThree ? [] : ledgerTwoPublishOptions),
        flags: ["--json", "-j", "--allow-unclassified"], usage: amendUsage)
    guard options.positionals.count == 1, options.value("--title") != nil else { usageFail(amendUsage) }
    guard context.isLedgerThree else {
        // ledger 2: 옛 발행의 --supersedes(반복하면 병합 개정).
        let store = context.ledgerStore
        var publish = ["publish"] + ledgerTwoCommonArguments(options)
        for token in [options.positionals[0]] + options.all("--also") {
            publish += ["--supersedes", resolve(store, token).id]
        }
        if options.has("--allow-unclassified") { publish.append("--allow-unclassified") }
        return runLedgerTwoPublish(context: context, arguments: publish)
    }
    let index = context.scopeIndex()
    let targets = resolveLawReferences([options.positionals[0]] + options.all("--also"), index: index)
    var draft = lawDraft(
        options: options, context: context, index: index,
        defaultType: index.object(id: targets[0])?.law?.type ?? LawRecordType.record.rawValue)
    draft.amends = targets[0]
    draft.amendsAlso = Array(targets.dropFirst())
    let stored = enactLaw(draft, context: context, index: index)
    printEnacted([stored.id], asJSON: options.has("--json"))
}
