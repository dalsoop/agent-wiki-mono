import Foundation
import KnowledgeBaseWikiCore

private func buildAdjacency(
    store: LedgerStore
) -> (adjacency: [String: [(next: String, label: String)]], label: (String) -> (title: String?, author: String)) {
    var adjacency: [String: [(next: String, label: String)]] = [:]
    let label: (String) -> (title: String?, author: String)
    if let index = freshIndex(store) {
        for e in index.citeEdges() {
            adjacency[e.src, default: []].append((e.dst, e.rel + " →"))
            adjacency[e.dst, default: []].append((e.src, "← " + e.rel))
        }
        for e in index.supersedesEdges() {
            adjacency[e.id, default: []].append((e.target, "supersedes →"))
            adjacency[e.target, default: []].append((e.id, "← supersedes"))
        }
        label = { index.titleAuthor($0) }
    } else {
        let objects = store.scan()
        for object in objects {
            for cite in object.cites {
                adjacency[object.id, default: []].append((cite.id, cite.rel + " →"))
                adjacency[cite.id, default: []].append((object.id, "← " + cite.rel))
            }
            if let target = object.supersedes {
                adjacency[object.id, default: []].append((target, "supersedes →"))
                adjacency[target, default: []].append((object.id, "← supersedes"))
            }
        }
        let byID = Dictionary(uniqueKeysWithValues: objects.map { ($0.id, $0) })
        label = { (byID[$0]?.title, byID[$0]?.author ?? "?") }
    }
    return (adjacency, label)
}

public func runPath(store: LedgerStore, arguments: [String]) {
    guard arguments.count >= 3 else { fail(usage) }
    let from = resolve(store, arguments[1])
    let to = resolve(store, arguments[2])
    let (adjacency, label) = buildAdjacency(store: store)
    var previous: [String: (id: String, label: String)] = [:]
    var queue = [from.id]
    var visited: Set<String> = [from.id]
    var found = false
    while !queue.isEmpty && !found {
        let current = queue.removeFirst()
        for (next, label) in adjacency[current] ?? [] where !visited.contains(next) {
            visited.insert(next)
            previous[next] = (current, label)
            if next == to.id { found = true; break }
            queue.append(next)
        }
    }
    guard found else {
        print("(경로 없음 — 두 객체가 인용 그래프에서 연결돼 있지 않음)") // allow:debug
        exit(0)
    }
    var chain: [(id: String, label: String?)] = [(to.id, nil)]
    var cursor = to.id
    while cursor != from.id, let previousStep = previous[cursor] {
        chain.append((previousStep.id, previousStep.label))
        cursor = previousStep.id
    }
    let ordered = Array(chain.reversed())
    for (index, step) in ordered.enumerated() {
        let (t, a) = label(step.id)
        print("\(step.id.prefix(8))  \(t ?? "(무제)")  — \(a)") // allow:debug
        if index + 1 < ordered.count, let label = step.label {
            print("   │ \(label)") // allow:debug
        }
    }
}

public func runHistory(store: LedgerStore, arguments: [String]) {
    guard arguments.count >= 2 else { fail(usage) }
    let target = resolve(store, arguments[1])
    if let index = freshIndex(store) {   // 인덱스로 supersedes 사슬 순회(파일 스캔 0)
        for (i, r) in index.lineage(of: target.id).enumerated() {
            print("\(i == 0 ? "→" : " ")\(r.id.prefix(8))  \(r.published)  \(r.author)  \(r.title ?? "")") // allow:debug
        }
        return
    }
    let objects = store.scan()
    for (index, object) in store.lineage(objects, of: target.id).enumerated() {
        print("\(index == 0 ? "→" : " ")\(object.id.prefix(8))  \(LedgerObject.iso.string(from: object.published))  \(object.author)  \(object.title ?? "")") // allow:debug
    }
}

public func runCitedBy(store: LedgerStore, arguments: [String]) {
    guard arguments.count >= 2 else { fail(usage) }
    let target = resolve(store, arguments[1])
    if let index = freshIndex(store) {   // cites 테이블 역인덱스(파일 스캔 0)
        let citers = index.citers(of: target.id)
        if citers.isEmpty { print("(인용 없음)") } // allow:debug
        for c in citers {
            print("\(c.id.prefix(8))  [\(c.rels)]  \(c.title ?? "(무제)")  — \(c.author)") // allow:debug
        }
        return
    }
    let objects = store.scan()
    let citing = store.citedBy(objects, id: target.id)
    if citing.isEmpty { print("(인용 없음)") } // allow:debug
    for object in citing {
        let rels = object.cites.filter { $0.id == target.id }.map(\.rel).joined(separator: ",")
        print("\(object.id.prefix(8))  [\(rels)]  \(object.title ?? "(무제)")  — \(object.author)") // allow:debug
    }
}
