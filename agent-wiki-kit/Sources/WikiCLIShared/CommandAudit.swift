import Foundation
import KnowledgeBaseWikiCore

// audit — 원장 무결성 감사. ledger 3 는 `LawStore.audit`(범위 해석기 주입), ledger 2 는 옛 verify 검사.
// 종료 코드: 0 통과, 2 위반. 근거: docs/contracts.md "agent-law 명령 (ledger 3)".

let auditUsage = "사용법: audit [--json]"

public func runAudit(context: LawCommandContext, arguments: [String]) {
    let options = LawOptions.parse(arguments, valued: [], usage: auditUsage)
    guard options.positionals.isEmpty else { usageFail(auditUsage) }
    guard context.isLedgerThree else {
        runVerify(
            store: context.ledgerStore, worlds: context.config.effectiveWorlds, repository: context.repository)
        return
    }
    let target = context.lawTarget()
    let report = target.store.audit(context: LawEnactService.context(index: context.scopeIndex()))
    let count = target.store.scan().count
    if options.has("--json") {
        struct Violation: Encodable { let id: String; let problem: String }
        struct Redacted: Encodable { let record: String; let exhibit: String }
        struct Divergent: Encodable { let amended: String; let heads: [String] }
        struct Result: Encodable {
            let world: String; let records: Int; let passed: Bool; let violations: [Violation]
            let pendingJudgment: [String]; let redacted: [Redacted]; let divergent: [Divergent]
        }
        struct Envelope: Encodable { let ok: Bool; let result: Result }
        printJSON(Envelope(ok: report.passed, result: Result(
            world: target.worldName, records: count, passed: report.passed,
            violations: report.violations.map { Violation(id: $0.id, problem: $0.problem) },
            pendingJudgment: report.pendingJudgment,
            redacted: report.redactedExhibits.map { Redacted(record: $0.recordID, exhibit: $0.sha256) },
            divergent: report.divergent.map { Divergent(amended: $0.amended, heads: $0.heads) })))
    } else if report.passed {
        print("이상 없음 (기록 \(count)개)") // allow:debug
    } else {
        for violation in report.violations { print("\(violation.id): \(violation.problem)") } // allow:debug
    }
    var notes: [String] = []
    if !report.pendingJudgment.isEmpty { notes.append("판단 대기 \(report.pendingJudgment.count)건") }
    if !report.redactedExhibits.isEmpty { notes.append("가림 \(report.redactedExhibits.count)건") }
    for divergence in report.divergent {
        notes.append("갈라진 현행 \(divergence.amended.prefix(8)) ← "
            + divergence.heads.map { String($0.prefix(8)) }.joined(separator: ", ") + " (amend --also 로 병합)")
    }
    if !notes.isEmpty {
        FileHandle.standardError.write(Data(("# " + notes.joined(separator: " · ") + "\n").utf8))
    }
    if !report.passed { exit(2) }
}
