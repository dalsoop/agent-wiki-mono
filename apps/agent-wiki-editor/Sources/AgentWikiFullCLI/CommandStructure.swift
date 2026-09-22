import Foundation
import KnowledgeBaseWikiCore
import LocalizationKit

/// structure [--json] — 저장 구조와 층 사이 배선 완성도를 실측해 보고한다.
/// 앱 "구조" 화면과 **같은 Core 계산**을 쓴다(수치가 갈라지지 않게).
func runStructure(store: LedgerStore, arguments: [String]) {
    let asJSON = arguments.contains("--json")
    let structure = LedgerStructure(root: store.root)

    if asJSON {
        struct Out: Encodable {
            let layers: [LedgerStructure.Layer]
            let edges: [EdgeOut]
            let satisfied: Int
            let required: Int
        }
        struct EdgeOut: Encodable {
            let id: String, from: String, to: String, label: String
            let actual: Int, total: Int
            let contract: String, status: String, note: String
        }
        let done = structure.completion
        printJSON(Out(
            layers: structure.layers,
            edges: structure.edges.map {
                EdgeOut(id: $0.id, from: $0.from, to: $0.to, label: $0.label,
                        actual: $0.actual, total: $0.total,
                        contract: $0.contract.rawValue, status: $0.status.rawValue, note: $0.note)
            },
            satisfied: done.satisfied, required: done.required))
        return
    }

    let done = structure.completion
    print(CLILocalization.text("CommandStructure.print", values: done.satisfied, done.required))

    print(CLILocalization.string("CommandStructure.print-2"))
    for layer in structure.layers {
        print("  \(layer.name)")
        print(CLILocalization.text("CommandStructure.print-3", values: layer.role, layer.files, humanBytes(layer.bytes)))
        for note in layer.notes { print("      · \(note)") }
    }

    print(CLILocalization.string("CommandStructure.print-4"))
    for edge in structure.edges {
        let mark: String
        switch edge.status {
        case .satisfied: mark = "●"
        case .partial: mark = "◐"
        case .missing: mark = "○"
        }
        let tag = edge.contract == .informational ? "관측" : (edge.contract == .invariant ? "불변" : "목표")
        let count = edge.total == 1
            ? (edge.actual == 1 ? "OK" : "미달")
            : "\(edge.actual)/\(edge.total)"
        print("  \(mark) [\(tag)] \(edge.label)  \(count)")
    }

    let breaches = structure.breaches
    guard !breaches.isEmpty else {
        print(CLILocalization.string("CommandStructure.print-5"))
        return
    }
    print(CLILocalization.format("CommandStructure.print-6", breaches.count))
    for edge in breaches {
        print("  · \(edge.label) — \(edge.note)")
    }
}

private func humanBytes(_ n: Int) -> String {
    if n >= 1_000_000 { return String(format: "%.1f MB", Double(n) / 1_000_000) }
    if n >= 1_000 { return String(format: "%.0f KB", Double(n) / 1_000) }
    return "\(n) B"
}
