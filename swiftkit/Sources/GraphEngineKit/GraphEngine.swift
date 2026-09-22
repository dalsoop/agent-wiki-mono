import Foundation

// MARK: - 그래프 구성요소 프로토콜 (도메인 무관)

/// 그래프 노드. id 는 String(함대 원장·레지스트리 모두 id 가 문자열).
/// `displayLabel` 은 alias 해상(본문 링크 → id)을 도메인 쪽에서 쓰기 위한 힌트일 뿐,
/// 엔진 자체는 label 을 해석하지 않는다 — 해상은 도메인 파서가 빌드 전에 끝낸다.
public protocol GraphNode: Identifiable, Sendable, Equatable where ID == String {
    var id: String { get }
    var displayLabel: String { get }
}

/// 방향 엣지. `kind` 는 필터링용 태그("cite"/"supersedes"/"depends-on"…),
/// `relation` 읔 세부 관계(cite 의 references/undercuts…). 둘 다 도메인이 정의.
public protocol GraphEdge: Sendable, Equatable {
    var from: String { get }
    var to: String { get }
    var kind: String { get }
    var relation: String? { get }
}

// MARK: - 방향 그래프 (제네릭)

/// 노드 dict + 순방향/역방향 인접 인덱스. swiftkit 에 범용 그래프가 없어 자체 구현.
///
/// 알고리즘(orphans·centrality·impact·path)은 이 안에서 닫는다 — 외부 의존성 0.
/// alias 해상(본문 wikilink → id)은 도메인 파서가 **빌드 전에** 끝낸다 — 엔진은
/// 들어온 엣지의 `to` 가 노드 집합에 없으면(dangling) 순회에서 무시한다.
public struct Graph<Node: GraphNode, Edge: GraphEdge>: Sendable {
    public let nodes: [String: Node]
    /// 순방향: from id → 그 노드가 내는 엣지들.
    public let out: [String: [Edge]]
    /// 역방향: to id → 그 노드로 들어오는 엣지들(impact·centrality 용).
    public let ins: [String: [Edge]]

    public init(nodes: [Node], edges: [Edge]) {
        var n: [String: Node] = [:]
        for node in nodes { n[node.id] = node }
        self.nodes = n
        var o: [String: [Edge]] = [:]
        var i: [String: [Edge]] = [:]
        for e in edges {
            o[e.from, default: []].append(e)
            i[e.to, default: []].append(e)
        }
        self.out = o
        self.ins = i
    }

    public var nodeCount: Int { nodes.count }
    public var edgeCount: Int { out.values.reduce(0) { $0 + $1.count } }
    /// 빈 그래프(진단/테스트용).
    public static func empty() -> Self where Node: GraphNode, Edge: GraphEdge {
        Graph<Node, Edge>(nodes: [], edges: [])
    }

    // MARK: - 알고리즘

    /// 한 노드로 들어오는 엣지 수(= 인기도/중심성). kinds 주면 그 kind 만.
    public func inDegree(of id: String, kinds: Set<String>? = nil) -> Int {
        guard let incoming = ins[id] else { return 0 }
        guard let kinds else { return incoming.count }
        return incoming.filter { kinds.contains($0.kind) }.count
    }

    /// in-degree=0 노드(아무도 가리키지 않는 고립).
    public func orphans(kinds: Set<String>? = nil) -> [Node] {
        nodes.values.filter { inDegree(of: $0.id, kinds: kinds) == 0 }.sorted { $0.id < $1.id }
    }

    /// 중심성 랭킹: in-degree desc. limit 주면 상위만.
    public func centrality(limit: Int? = nil, kinds: Set<String>? = nil) -> [(node: Node, degree: Int)] {
        let ranked = nodes.values
            .map { (node: $0, degree: inDegree(of: $0.id, kinds: kinds)) }
            .sorted { lhs, rhs in
                if lhs.degree != rhs.degree { return lhs.degree > rhs.degree }
                return lhs.node.id < rhs.node.id
            }
        return limit.map { Array(ranked.prefix($0)) } ?? ranked
    }

    /// 임팩트: `id` 에 (전이적으로) 의존하는 노드 전체(역방향 BFS). `id` 자신 제외.
    public func impact(of id: String, kinds: Set<String>? = nil) -> [Node] {
        var seen: Set<String> = [id]
        var queue: [String] = [id]
        while !queue.isEmpty {
            let cur = queue.removeFirst()
            guard let incoming = ins[cur] else { continue }
            for e in incoming where kinds == nil || kinds!.contains(e.kind) {
                if seen.insert(e.from).inserted { queue.append(e.from) }
            }
        }
        seen.remove(id)
        return seen.compactMap { nodes[$0] }.sorted { $0.id < $1.id }
    }

    /// 순방향 경로: a → … → b (BFS). 못 찾으면 nil. 경로는 id 시퀀스(a,b 포함).
    public func path(from a: String, to b: String, kinds: Set<String>? = nil) -> [String]? {
        guard nodes[a] != nil, nodes[b] != nil else { return nil }
        if a == b { return [a] }
        var prev: [String: String] = [:]
        var queue: [String] = [a]
        var seen: Set<String> = [a]
        while !queue.isEmpty {
            let cur = queue.removeFirst()
            guard let outgoing = out[cur] else { continue }
            for e in outgoing where kinds == nil || kinds!.contains(e.kind) {
                if nodes[e.to] == nil { continue } // dangling 무시
                if seen.insert(e.to).inserted {
                    prev[e.to] = cur
                    if e.to == b { return reconstruct(prev: prev, from: a, to: b) }
                    queue.append(e.to)
                }
            }
        }
        return nil
    }

    private func reconstruct(prev: [String: String], from start: String, to end: String) -> [String] {
        var p: [String] = [end]
        var cur = end
        while cur != start, let parent = prev[cur] { p.append(parent); cur = parent }
        return p.reversed()
    }
}
