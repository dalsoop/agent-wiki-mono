import Foundation
import KnowledgeBaseWikiCore
import LocalizationKit

/// 파생 그래프(graph.db) 조종 — 객체+사건 순회 질의. md·events 정본에서 재빌드.
func runGraph(store: LedgerStore, root: URL, arguments: [String]) {
    let sub = arguments.count >= 2 ? arguments[1] : "status"
    let graph = LedgerGraph(root: root)
    switch sub {
    case "rebuild":
        let objects = store.scan()
        let events = EventLog(root: root).all()
        graph.rebuild(objects: objects, events: events)
        let c = graph.counts()
        print(CLILocalization.format("CommandGraph.print", c.nodes, c.edges, objects.count, events.count))

    case "status":
        let c = graph.counts()
        print(CLILocalization.format("CommandGraph.print-2", c.nodes, c.edges, graph.path))

    case "timeline":
        guard arguments.count >= 3 else { fail("graph timeline <id접두어>") }
        let target = resolve(store, arguments[2])
        let rows = graph.timeline(of: target.id)
        if rows.isEmpty { print(CLILocalization.string("CommandGraph.print-3")) }
        for r in rows { print("\(r.occurred)  [\(r.rel)] \(r.role)  (\(r.eventID.prefix(8)))") }

    case "neighbors":
        guard arguments.count >= 3 else { fail("graph neighbors <id접두어>") }
        let target = resolve(store, arguments[2])
        for n in graph.neighbors(of: target.id) {
            let arrow = n.direction == "out" ? "→" : "←"
            print("\(arrow) [\(n.rel)/\(n.kind)] \(n.id.prefix(12))")
        }

    case "interpretations":
        // 한 사건을 observes 로 가리키는 해석 객체들 — 같은 사실에 대한 경합하는 판단.
        guard arguments.count >= 3 else { fail("graph interpretations <event-id>") }
        let ids = graph.interpretations(of: arguments[2])
        if ids.isEmpty { print(CLILocalization.string("CommandGraph.print-4")) }
        for id in ids {
            let title = store.find(store.scan(), idPrefix: id)?.title ?? id
            print("\(id.prefix(8))  \(title)")
        }

    default:
        fail(usage)
    }
}
