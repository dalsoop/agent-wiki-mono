import Foundation
import KnowledgeBaseWikiCore

/// 파생 그래프(graph.db) 조종 — 객체+사건 순회 질의. md·events 정본에서 재빌드.
public func runGraph(store: LedgerStore, root: URL, arguments: [String]) {
    let sub = arguments.count >= 2 ? arguments[1] : "status"
    let graph = LedgerGraph(root: root)
    switch sub {
    case "rebuild":
        let objects = store.scan()
        let events = EventLog(root: root).all()
        graph.rebuild(objects: objects, events: events)
        let c = graph.counts()
        print("그래프 재구성: 노드 \(c.nodes)개 · 간선 \(c.edges)개 (객체 \(objects.count) · 사건 \(events.count))") // allow:debug

    case "status":
        let c = graph.counts()
        print("그래프 노드 \(c.nodes)개 · 간선 \(c.edges)개 · \(graph.path)") // allow:debug

    case "timeline":
        guard arguments.count >= 3 else { fail("graph timeline <id접두어>") }
        let target = resolve(store, arguments[2])
        let rows = graph.timeline(of: target.id)
        if rows.isEmpty { print("(사건 없음 — graph rebuild 했는지 확인)") } // allow:debug
        for r in rows { print("\(r.occurred)  [\(r.rel)] \(r.role)  (\(r.eventID.prefix(8)))") } // allow:debug

    case "neighbors":
        guard arguments.count >= 3 else { fail("graph neighbors <id접두어>") }
        let target = resolve(store, arguments[2])
        for n in graph.neighbors(of: target.id) {
            let arrow = n.direction == "out" ? "→" : "←"
            print("\(arrow) [\(n.rel)/\(n.kind)] \(n.id.prefix(12))") // allow:debug
        }

    case "interpretations":
        // 한 사건을 observes 로 가리키는 해석 객체들 — 같은 사실에 대한 경합하는 판단.
        guard arguments.count >= 3 else { fail("graph interpretations <event-id>") }
        let ids = graph.interpretations(of: arguments[2])
        if ids.isEmpty { print("(해석 없음)") } // allow:debug
        for id in ids {
            let title = store.find(store.scan(), idPrefix: id)?.title ?? id
            print("\(id.prefix(8))  \(title)") // allow:debug
        }

    default:
        fail(usage)
    }
}
