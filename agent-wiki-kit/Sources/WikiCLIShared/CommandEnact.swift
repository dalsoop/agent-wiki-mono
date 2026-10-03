import Foundation
import KnowledgeBaseWikiCore
import WikiLedgerKit

// enact — 공포. ledger 3 원장은 `LawEnactService`(쓰기 게이트·범위 해석기·후처리),
// ledger 2 원장은 옛 발행 경로(`runWorldAwarePublish`)로 간다.
// 근거: docs/contracts.md "agent-law 명령 (ledger 3)", 결정 0007.

let enactUsage = """
사용법: enact --title <t> [--type <유형>] [--tag <t>]… [--cite <id>[:<rel>]]… [--exhibit <sha>]…
              [--speaker <s>] [--batch <id>] [--runtime <r>] [--model <m>] [--effort <e>]
              [--runtime-version <v>] [--app <slug>] [--app-version <v>] [--json]   (본문 표준 입력)
"""

/// enact·amend 가 함께 받는 값 옵션.
let enactValueOptions: Set<String> = Set([
    "--title", "--type", "--tag", "--cite", "--exhibit", "--speaker", "--batch",
]).union(LawOptions.modelOptions)

/// ledger 2 원장 enact 가 옛 발행으로 넘기는 추가 옵션(옛 발행 표면 그대로).
let ledgerTwoPublishOptions: Set<String> = [
    "--origin", "--alias", "--observes", "--domain", "--kind", "--knowledge", "--classification-reason",
]

/// `--cite <id>[:<rel>]` → (토큰, 관계). 관계를 생략하면 `cites`.
func splitCite(_ raw: String) -> (token: String, rel: String) {
    guard let colon = raw.firstIndex(of: ":") else { return (raw, LawRelation.cites.rawValue) }
    let rel = String(raw[raw.index(after: colon)...])
    return (String(raw[..<colon]), rel.isEmpty ? LawRelation.cites.rawValue : rel)
}

/// 참조 토큰 → 범위 안 64자 id(실패면 거부 1).
func resolveLawReferences(_ tokens: [String], index: LawScopeIndex) -> [String] {
    do { return try LawEnactService.resolveReferences(tokens, index: index) } catch { lawFail(error) }
}

/// ledger 3 공포 공통: 쓰기는 `LawEnactService.enact` 하나.
func enactLaw(_ draft: LawDraft, context: LawCommandContext, index: LawScopeIndex) -> LawStoredRecord {
    do {
        return try LawEnactService.enact(draft, target: context.lawTarget(), index: index)
    } catch {
        lawFail(error)
    }
}

/// enact/amend 의 공통 초안(본문은 표준 입력).
func lawDraft(
    options: LawOptions, context: LawCommandContext, index: LawScopeIndex,
    defaultType: String = LawRecordType.record.rawValue
) -> LawDraft {
    let cites = options.all("--cite").map(splitCite)
    let ids = resolveLawReferences(cites.map(\.token), index: index)
    let actor = context.actor(explicit: options.modelRecord)
    let body = readStandardInputBody()
    return LawDraft(
        actor: actor, speaker: options.value("--speaker"), title: options.value("--title"),
        type: options.value("--type") ?? defaultType,
        batch: options.value("--batch") ?? context.environment["MEMO_LEDGER_BATCH"],
        tags: options.all("--tag"),
        cites: zip(ids, cites).map { LawCite(id: $0.0, rel: $0.1.rel) },
        exhibits: options.all("--exhibit"), body: body)
}

public func runEnact(context: LawCommandContext, arguments: [String]) {
    guard context.isLedgerThree else { return runLedgerTwoEnact(context: context, arguments: arguments) }
    let options = LawOptions.parse(arguments, valued: enactValueOptions, usage: enactUsage)
    guard options.positionals.isEmpty else { usageFail(enactUsage) }
    let index = context.scopeIndex()
    let draft = lawDraft(options: options, context: context, index: index)
    let stored = enactLaw(draft, context: context, index: index)
    printEnacted([stored.id], asJSON: options.has("--json"))
}

// MARK: - ledger 2 원장(novel-world·repo world)

/// ledger 2 원장 enact — 옛 발행 인자로 옮겨 `runWorldAwarePublish` 를 부른다.
func runLedgerTwoEnact(context: LawCommandContext, arguments: [String]) {
    let options = LawOptions.parse(
        arguments, valued: enactValueOptions.union(ledgerTwoPublishOptions),
        flags: ["--json", "-j", "--allow-unclassified"], usage: enactUsage)
    guard options.positionals.isEmpty else { usageFail(enactUsage) }
    var publish = ["publish"] + ledgerTwoCommonArguments(options)
    if options.has("--allow-unclassified") { publish.append("--allow-unclassified") }
    runLedgerTwoPublish(context: context, arguments: publish)
}

/// enact/amend 공통 옵션 → 옛 발행 인자. ledger 2 형식에 없는 칸(`--speaker`·`--exhibit`)은 거부한다.
func ledgerTwoCommonArguments(_ options: LawOptions) -> [String] {
    if options.value("--speaker") != nil || !options.all("--exhibit").isEmpty {
        fail("ledger 2 원장은 --speaker·--exhibit 를 받지 않는다")
    }
    var out: [String] = []
    for flag in ["--title", "--type", "--batch"] + ledgerTwoPublishOptions.sorted() {
        for value in options.all(flag) { out += [flag, value] }
    }
    for tag in options.all("--tag") { out += ["--tag", tag] }
    for raw in options.all("--cite") {
        let cite = splitCite(raw)
        out += ["--cite", cite.token, cite.rel]
    }
    return out
}

func runLedgerTwoPublish(context: LawCommandContext, arguments: [String]) {
    context.ledgerTwo.checkWritePermission()
    let world = context.requireWorld()
    runWorldAwarePublish(
        store: context.ledgerStore, worldName: world.name, author: context.author,
        arguments: arguments, catalog: context.catalog, copy: context.ledgerTwo.publishCopy)
}
