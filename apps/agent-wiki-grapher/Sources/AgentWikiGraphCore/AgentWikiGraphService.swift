import Foundation
import StateMirrorKit
import GraphEngineKit
import GraphRAGKit
import WikiLedgerKit
import AppPathsKit

/// AgentWikiGraph 도메인 로직 — 원장을 read-only 로 읽어 파생 그래프를 내고, 그 위의
/// 질의(orphans·centrality·impact·path)를 담당한다. CLI·GUI 양쪽이 같은 Core 경로를
/// 호출한다(4면 계약). **원장을 결코 쓰지 않는다.** 그래프 수학은 GraphEngineKit 에,
/// 위키 파싱은 WikiLedgerKit 에 위임.
public struct AgentWikiGraphService: Sendable {
    public let root: URL
    private let cacheURL: URL

    public init(root: URL? = nil, cacheURL: URL? = nil) {
        self.root = root ?? GraphIndexer.defaultRoot()
        self.cacheURL = cacheURL ?? IndexCache.defaultURL
    }

    // MARK: - 로드

    /// 캐시 우선 증분 로드(원장 mtime 변하면 재빌드).
    public func loadGraph() -> Graph<WikiNode, WikiEdge> {
        GraphIndexer.load(root: root, cacheURL: cacheURL)
    }

    /// 전체 재빌드 후 캐시 저장.
    @discardableResult
    public func rebuild() -> Graph<WikiNode, WikiEdge> {
        let graph = GraphIndexer.rebuild(root: root)
        IndexCache.save(
            url: cacheURL,
            .init(version: IndexCache.currentVersion,
                  ledgerFingerprint: GraphIndexer.ledgerFingerprint(root: root),
                  nodes: Array(graph.nodes.values), edges: graph.out.values.flatMap { $0 },
                  nodeCount: graph.nodeCount, edgeCount: graph.edgeCount,
                  orphanCount: graph.orphans().count, indexedAt: Date())
        )
        return graph
    }

    // MARK: - 관측 계약(싸게)

    public struct StatusSummary: Codable, Sendable {
        public var root: String
        public var objectFileCount: Int
        public var nodeCount: Int
        public var edgeCount: Int
        public var orphanCount: Int
        public var ledgerFingerprint: String
        public var indexedAt: Date?
    }

    public func status() -> StatusSummary {
        let g = loadGraph()
        let snap = IndexCache.load(url: cacheURL)
        return StatusSummary(
            root: root.path,
            objectFileCount: GraphIndexer.objectFileCount(root: root),
            nodeCount: g.nodeCount,
            edgeCount: g.edgeCount,
            orphanCount: g.orphans().count,
            ledgerFingerprint: snap?.ledgerFingerprint ?? GraphIndexer.ledgerFingerprint(root: root),
            indexedAt: snap?.indexedAt
        )
    }

    // MARK: - 질의

    public func orphans(kinds: Set<WikiEdgeKind>? = nil) -> [WikiNode] {
        loadGraph().orphans(kinds: kinds.map { Set($0.map(\.rawValue)) })
    }

    public func centrality(limit: Int, kinds: Set<WikiEdgeKind>? = nil) -> [(WikiNode, Int)] {
        loadGraph().centrality(limit: limit, kinds: kinds.map { Set($0.map(\.rawValue)) }).map { ($0.node, $0.degree) }
    }

    public func impact(of idPrefix: String, kinds: Set<WikiEdgeKind>? = nil) -> [WikiNode]? {
        guard let id = resolve(prefix: idPrefix) else { return nil }
        return loadGraph().impact(of: id, kinds: kinds.map { Set($0.map(\.rawValue)) })
    }

    public func path(from aPrefix: String, to bPrefix: String, kinds: Set<WikiEdgeKind>? = nil) -> (path: [String], nodes: [WikiNode])? {
        guard let a = resolve(prefix: aPrefix), let b = resolve(prefix: bPrefix) else { return nil }
        let g = loadGraph()
        guard let ids = g.path(from: a, to: b, kinds: kinds.map { Set($0.map(\.rawValue)) }) else { return nil }
        let ns = ids.compactMap { g.nodes[$0] }
        return (ids, ns)
    }

    /// GraphRAG(관계 인식 검색): 질의 토큰 시드 → 이웃 확장 → in-degree 순위.
    /// 평 텍스트 검색과 달리 시드의 그래프 문맥(인접·역인용)까지 끌어온다.
    public func context(_ query: String, limit: Int = 20) -> [(node: WikiNode, score: Int, seed: Bool)] {
        let g = loadGraph()
        return GraphRAG.retrieve(query, in: g, textOf: { "\($0.title) \($0.type)" }, limit: limit)
            .map { ($0.node, $0.score, $0.seed) }
    }

    // MARK: - private

    /// 접두어로 노드 id 를 하나로 확정. 안 되면 nil(전체 id 또는 고유 접두어를 주게).
    func resolve(prefix: String) -> String? {
        if prefix.count >= 64 { return prefix } // 이미 전체 id
        let g = loadGraph()
        let matches = g.nodes.keys.filter { $0.hasPrefix(prefix) }
        return matches.count == 1 ? matches.first : nil
    }

    public func ensureDurableStore() throws {
        try DurableAppLayout.ensureDatabase(at: DurableAppLayout.sqliteURL(slug: "agent-wiki-graph"))
    }
}
