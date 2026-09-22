import Foundation
import GraphEngineKit

/// 관계 인식 검색(GraphRAG) — 범용. GraphEngineKit.Graph 위에서 도메인 무관으로 돈다.
///
/// 평 텍스트 검색이 질의 토큰이 맞는 노드만 찾는다면, GraphRAG 는 그 시드 노드의
/// **이웃(그래프 문맥)** 까지 확장해 in-degree 로 순위 매긴다. 위키·함대·세션 어떤
/// 그래프 위에서든 쓴다(텍스트 추출은 호출측에서 `textOf` 클로저로 준다).
public enum GraphRAG {

    public struct Hit<Node: GraphNode>: Sendable {
        public let node: Node
        public let score: Int
        public let seed: Bool   // 직접 토큰 매칭된 시드면 true, 이웃 확장이면 false
    }

    /// 질의 → 시드(토큰 매칭) → 이웃 확장 → 순위.
    /// - Parameters:
    ///   - query: 질의 문장(토큰화됨).
    ///   - graph: 검색 대상 그래프.
    ///   - textOf: 노드의 검색 가능 텍스트(제목·요약 등)를 내는 클로저.
    ///   - limit: 상위 N.
    ///   - expandHops: 시드에서 몇 홉까지 이웃을 확장할까(기본 1).
    public static func retrieve<Node, Edge>(
        _ query: String,
        in graph: Graph<Node, Edge>,
        textOf: (Node) -> String,
        limit: Int = 20,
        expandHops: Int = 1
    ) -> [Hit<Node>] where Node: GraphNode, Edge: GraphEdge {
        let tokens = tokenize(query)
        guard !tokens.isEmpty else { return [] }

        // 1) 시드: 노드 텍스트가 토큰을 하나라도 포함.
        var scores: [String: Int] = [:]
        var seeds: Set<String> = []
        for node in graph.nodes.values {
            let text = textOf(node).lowercased()
            var hits = 0
            for t in tokens where text.contains(t) { hits += 1 }
            if hits > 0 {
                scores[node.id] = hits * 10
                seeds.insert(node.id)
            }
        }
        guard !seeds.isEmpty else { return [] }

        // 2) 확장: 시드의 이웃(expandHops 홉)에 보너스 + in-degree 반영.
        var frontier = Array(seeds)
        var seen = Set(seeds)
        for hop in 1...max(1, expandHops) {
            let next = frontier
            frontier = []
            for id in next {
                let bonus = max(1, 5 - hop)  // 가까울수록 큰 보너스
                // 순방향 이웃
                for e in graph.out[id] ?? [] where graph.nodes[e.to] != nil {
                    if seen.insert(e.to).inserted { frontier.append(e.to) }
                    scores[e.to, default: 0] += bonus
                }
                // 역방향 이웃(이 노드를 인용한 것 — 영향 맥락)
                for e in graph.ins[id] ?? [] where graph.nodes[e.from] != nil {
                    if seen.insert(e.from).inserted { frontier.append(e.from) }
                    scores[e.from, default: 0] += bonus
                }
            }
        }
        // in-degree 가 높을수록(허브) 약간 가산.
        for id in scores.keys {
            scores[id, default: 0] += min(5, graph.inDegree(of: id))
        }

        // 3) 순위.
        return scores
            .compactMap { (id, score) -> Hit<Node>? in
                guard let node = graph.nodes[id] else { return nil }
                return Hit(node: node, score: score, seed: seeds.contains(id))
            }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.node.id < rhs.node.id
            }
            .prefix(limit)
            .map { $0 }
    }

    /// 간단 토큰화: 소문자화 + 공백/구두점 분리 + 길이 1 이상 + stopword 제거.
    /// (한국어 어미 정규화는 도메인 쪽에서 미리 해서 textOf 에 담아도 된다.)
    public static func tokenize(_ query: String) -> [String] {
        let stop: Set<String> = ["the","a","an","of","to","in","on","for","and","or","is","이","를","을","가","은","는","및","에","의"]
        return query.lowercased()
            .split(whereSeparator: { $0.isWhitespace || $0.isPunctuation })
            .map { String($0) }
            .filter { $0.count > 1 && !stop.contains($0) }
    }
}
