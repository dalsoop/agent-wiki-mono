import Foundation
import KnowledgeBaseWikiCore

public func runShow(store: LedgerStore, arguments: [String]) {
    guard arguments.count >= 2 else { fail(usage) }
    print(resolve(store, arguments[1]).serialize(), terminator: "") // allow:debug
}

private struct ListRow: Encodable {
    let id: String; let title: String?; let author: String; let published: String; let batch: String?
    let supersedes: String?; let retracts: String?
}

private func printListOutput(_ rows: [ListRow], asJSON: Bool) {
    if asJSON {
        struct Envelope: Encodable { let ok: Bool; let result: Result }
        struct Result: Encodable { let objects: [ListRow]; let note: String }
        let note = rows.isEmpty ? "객체 없음 — agent-wiki publish 로 발행하세요" : "\(rows.count) objects"
        printJSON(Envelope(ok: true, result: Result(objects: rows, note: note)))
    } else {
        if rows.isEmpty { print("(객체 없음)") } // allow:debug
        for r in rows {
            let marks = [r.supersedes != nil ? "개정" : nil, r.retracts != nil ? "철회발행" : nil]
                .compactMap { $0 }.joined(separator: ",")
            print("\(r.id.prefix(8))  \(r.title ?? "(무제)")  — \(r.author)" + (marks.isEmpty ? "" : "  [\(marks)]")) // allow:debug
        }
    }
}

private func listFromIndex(store: LedgerStore, all: Bool, asJSON: Bool) {
    let index = LedgerIndex(root: store.root)
    index.ensureFresh(objectsDir: store.root.appendingPathComponent("objects"))
    let rows = index.headRows(all: all).map {
        ListRow(id: $0.id, title: $0.title, author: $0.author, published: $0.published,
                batch: $0.batch, supersedes: $0.supersedes, retracts: $0.retracts)
    }
    printListOutput(rows, asJSON: asJSON)
}

private func listFromScan(store: LedgerStore, all: Bool, asJSON: Bool) {
    let objects = store.scan()
    let rows = (all ? objects : store.heads(objects)).map {
        ListRow(id: $0.id, title: $0.title, author: $0.author,
                published: LedgerObject.iso.string(from: $0.published),
                batch: $0.batch, supersedes: $0.supersedes, retracts: $0.retracts)
    }
    printListOutput(rows, asJSON: asJSON)
}

public func runList(store: LedgerStore, arguments: [String]) {
    let all = arguments.contains("--all")
    let asJSON = arguments.contains("--json")
    let indexPath = store.root.appendingPathComponent("state/index.db")
    if FileManager.default.fileExists(atPath: indexPath.path) {
        listFromIndex(store: store, all: all, asJSON: asJSON)
    } else {
        listFromScan(store: store, all: all, asJSON: asJSON)
    }
}
