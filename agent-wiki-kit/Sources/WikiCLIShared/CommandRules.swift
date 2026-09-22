import Foundation
import KnowledgeBaseWikiCore

/// 경험칙 조회 — 한 역할 실행 시 프롬프트에 주입될 회고(경험칙)를 미리 본다(SPL 투명성).
public func runRules(store: LedgerStore, arguments: [String]) {
    let role = arguments.count >= 2 ? arguments[1] : ""
    let rules = store.experienceRules(store.scan(), forRole: role)
    if rules.isEmpty { print("(경험칙 없음\(role.isEmpty ? "" : " — \(role)"))"); return } // allow:debug
    print("경험칙 \(rules.count)건\(role.isEmpty ? "" : " (역할 \(role) 실행 시 주입)"):") // allow:debug
    for r in rules { print("- \((r.title ?? "").replacingOccurrences(of: "회고: ", with: ""))  (\(r.author))") } // allow:debug
}
