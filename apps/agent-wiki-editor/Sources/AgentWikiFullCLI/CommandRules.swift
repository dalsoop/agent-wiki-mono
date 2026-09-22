import Foundation
import KnowledgeBaseWikiCore
import LocalizationKit

/// 경험칙 조회 — 한 역할 실행 시 프롬프트에 주입될 회고(경험칙)를 미리 본다(SPL 투명성).
func runRules(store: LedgerStore, arguments: [String]) {
    let role = arguments.count >= 2 ? arguments[1] : ""
    let rules = store.experienceRules(store.scan(), forRole: role)
    if rules.isEmpty { print(CLILocalization.format("CommandRules.print", role.isEmpty ? "" : " — \(role)")); return }
    print(CLILocalization.format("CommandRules.print-2", rules.count, role.isEmpty ? "" : CLILocalization.format("cli.role-inject", role)))
    for r in rules { print(CLILocalization.format("CommandRules.print-3", (r.title ?? "").replacingOccurrences(of: CLILocalization.string("cli.retrospect-prefix"), with: ""), r.author)) }
}
