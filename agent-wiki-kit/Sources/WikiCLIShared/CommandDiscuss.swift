import Foundation
import KnowledgeBaseWikiCore

/// 위키 토론 — 나무위키 토론 대응. 미답변(사서 처리 대상) 우선.
public func runDiscuss(store: LedgerStore, arguments: [String]) {
    let threads = store.discussionThreads(store.scan())
    let open = threads.filter(\.isOpen).count
    print("토론 \(threads.count)건 · 미답변 \(open)") // allow:debug
    for t in threads {
        let state = t.isOpen ? "● 미답변" : "○ 답변\(t.responseCount)"
        print("\(state)  [\(t.kind.label)] \(t.title)  (\(t.author))") // allow:debug
    }
}
