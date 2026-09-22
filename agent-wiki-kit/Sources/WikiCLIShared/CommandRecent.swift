import Foundation
import KnowledgeBaseWikiCore

/// 지식층 최근 변경 피드 — 나무위키 RecentChanges. 신규·개정·철회를 시간순으로.
public func runRecent(store: LedgerStore, arguments: [String]) {
    let n = arguments.count >= 2 ? (Int(arguments[1]) ?? 30) : 30
    let changes = store.recentChanges(store.scan(), limit: n)
    if changes.isEmpty { print("(변경 없음)"); return } // allow:debug
    let iso = ISO8601DateFormatter()
    for c in changes {
        let mark: String
        switch c.kind {
        case .new: mark = "신규"
        case .revised: mark = c.deltaChars >= 0 ? "개정 +\(c.deltaChars)" : "개정 \(c.deltaChars)"
        case .retracted: mark = "철회"
        }
        var line = "\(iso.string(from: c.published))  [\(mark)] \(c.title)  (\(c.author))"
        if let r = c.reason { line += "  — \(r.prefix(40))" }
        print(line) // allow:debug
    }
}
