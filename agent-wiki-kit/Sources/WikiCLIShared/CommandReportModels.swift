import Foundation
import KnowledgeBaseWikiCore

// report models — 모델·추론 강도·실행 도구별 공포 건수와 개정·폐지·뒤집힌 비율. 본체는 `LawModelReport`.
// 계약: docs/contracts.md "agent-law 명령 (ledger 3)" — `report models [--since <t>]`.
// 규칙: docs/business-rules.md "드리밍"(측정만 하고 자동 가중치로 쓰지 않는다).

let reportUsage = "사용법: report models [--since <t>] [--json]"

public func runReport(context: LawCommandContext, arguments: [String]) {
    guard arguments.count >= 2, arguments[1] == "models" else { usageFail(reportUsage) }
    guard context.isLedgerThree else { usageFail("report 는 ledger 3 원장 전용") }
    let options = LawOptions.parse(arguments, skip: 2, valued: ["--since"], usage: reportUsage)
    guard options.positionals.isEmpty else { usageFail(reportUsage) }
    var since: Date?
    if let raw = options.value("--since") {
        guard let parsed = LawSummonQuery.parseTime(raw) else { usageFail("--since 시각을 읽을 수 없음: \(raw)\n\(reportUsage)") }
        since = parsed
    }
    let rows = LawModelReport.rows(records: context.lawTarget().store.scan(), since: since)
    if options.has("--json") {
        struct Result: Encodable { let world: String; let since: String?; let rows: [LawModelReportRow] }
        struct Envelope: Encodable { let ok: Bool; let result: Result }
        printJSON(Envelope(ok: true, result: Result(
            world: context.requireWorld().name, since: options.value("--since"), rows: rows)))
        return
    }
    func percent(_ value: Double) -> String { String(format: "%.1f%%", value * 100) }
    print("runtime\tmodel\teffort\t공포\t개정\t폐지\t뒤집힘") // allow:debug — 명령 결과 출력
    for row in rows {
        print([row.runtime, row.model, row.effort, String(row.enacted), percent(row.amendedRate),
               percent(row.repealedRate), percent(row.overturnedRate)].joined(separator: "\t")) // allow:debug
    }
}
