import AppScaffoldKit
import XCTest
import GraphEngineKit
import WikiLedgerKit
import StateRootKit
@testable import AgentWikiGraphCore

final class SmokeTests: XCTestCase {
    func testAppFormContractCompliance() {
        XCTAssertTrue(RanodeAppFormContract.assertConforms(slug: "agent-wiki-graph"))
    }


    // MARK: - 파서 (WikiLedgerKit)

    /// frontmatter 의 반복 `cite:` 키와 rel, supersedes, 본문 wikilink 가 정확히 뽑히는가.
    func testParserParsesTypedEdges() {
        let raw = """
        ---
        ledger: 2
        id: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
        published: 2026-08-09T00:00:00.000Z
        author: agent:claude@macbook
        title: 근거: 테스트 객체 A
        type: evidence
        cite: bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb references
        cite: cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc undercuts
        supersedes: dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
        ---

        본문. [[관련 객체 E]] 와 instance-of: ffffffff.
        """
        guard let parsed = WikiLedgerParser.parse(raw: raw, relativePath: "objects/2026/08/aaaa.md") else {
            return XCTFail("파싱 실패")
        }
        let node = parsed.node
        let edges = parsed.edges

        XCTAssertEqual(node.type, "evidence")
        XCTAssertEqual(node.title, "근거: 테스트 객체 A")
        XCTAssertEqual(node.id.count, 64)

        let cites = edges.filter { $0.displayKind == .cite }
        XCTAssertEqual(cites.count, 2)
        XCTAssertTrue(cites.contains { $0.relation == "references" })
        XCTAssertTrue(cites.contains { $0.relation == "undercuts" })

        XCTAssertTrue(edges.contains { $0.displayKind == .supersedes })
        XCTAssertTrue(edges.contains { $0.displayKind == .wikilink })
    }

    /// id 없는 깨진 객체는 nil.
    func testParserRejectsBrokenObject() {
        let raw = """
        ---
        type: evidence
        title: id 없음
        ---

        본문.
        """
        XCTAssertNil(WikiLedgerParser.parse(raw: raw, relativePath: "x.md"))
    }

    /// 공용 gujo-wiki 는 tenant current-context overlay 가 아니다.
    func testDefaultRootIgnoresTenantContextOverlay() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("wiki-graph-home-\(UUID().uuidString)")
        let ctxDir = home.appendingPathComponent(".agent-tenant-isolation-manager")
        try FileManager.default.createDirectory(at: ctxDir, withIntermediateDirectories: true)
        try Data("{\"tenantID\":\"tenant:personal\"}".utf8)
            .write(to: ctxDir.appendingPathComponent("current-context.json"))
        let env: [String: String] = [:]
        let tenantOverlay = StateRootKit.url(
            "gujo-wiki",
            environment: env,
            homeDirectory: home.path
        )
        XCTAssertTrue(tenantOverlay.path.contains("/.tenants/personal/"))
        let graphRoot = GraphIndexer.defaultRoot(environment: env, homeDirectory: home.path)
        XCTAssertEqual(
            graphRoot.path,
            (home.path as NSString).appendingPathComponent("gujo-wiki")
        )
        XCTAssertFalse(graphRoot.path.contains("/.tenants/"))
    }

    // MARK: - 그래프 알고리즘 (GraphEngineKit.Graph)

    /// 고립(orphans): 아무도 가리키지 않는 루트 노드만. 중심성: 여러 엣지 받는 노드가 1위.
    func testOrphansAndCentrality() {
        let a = node("a", "A"); let b = node("b", "B"); let c = node("c", "C")
        let edges = [
            WikiEdge(from: "a", to: "b", kind: .cite, relation: "references"),
            WikiEdge(from: "b", to: "c", kind: .cite, relation: "references"),
            WikiEdge(from: "a", to: "c", kind: .cite, relation: "cites"),
        ]
        let g = Graph<WikiNode, WikiEdge>(nodes: [a, b, c], edges: edges)

        XCTAssertEqual(g.orphans().map(\.id).sorted(), ["a"], "a 만 in-degree 0")

        let top = g.centrality(limit: 1)
        XCTAssertEqual(top.first?.node.id, "c")
        XCTAssertEqual(top.first?.degree, 2)
    }

    /// impact: c 를 바꾸면 a, b 가 흔들린다(역의존). 자신 제외.
    func testImpactReverseReachable() {
        let a = node("a", "A"); let b = node("b", "B"); let c = node("c", "C")
        let edges = [
            WikiEdge(from: "a", to: "b", kind: .cite),
            WikiEdge(from: "b", to: "c", kind: .cite),
            WikiEdge(from: "a", to: "c", kind: .cite),
        ]
        let g = Graph<WikiNode, WikiEdge>(nodes: [a, b, c], edges: edges)
        XCTAssertEqual(g.impact(of: "c").map(\.id).sorted(), ["a", "b"])
    }

    /// path: a → b → c 순방향. 단절은 nil.
    func testPathTraversal() {
        let a = node("a", "A"); let b = node("b", "B"); let c = node("c", "C"); let z = node("z", "Z")
        let edges = [
            WikiEdge(from: "a", to: "b", kind: .cite),
            WikiEdge(from: "b", to: "c", kind: .cite),
        ]
        let g = Graph<WikiNode, WikiEdge>(nodes: [a, b, c, z], edges: edges)
        XCTAssertEqual(g.path(from: "a", to: "c"), ["a", "b", "c"])
        XCTAssertNil(g.path(from: "a", to: "z"))
    }

    /// wikilink alias 가 title→id 로 해상되는가 (WikiLedgerIndex.buildGraph).
    func testWikilinkAliasResolutionViaIndex() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("awg-\(UUID().uuidString)")
        let objectsDir = dir.appendingPathComponent("objects/2026/08")
        try FileManager.default.createDirectory(at: objectsDir, withIntermediateDirectories: true)
        try writeObject(at: objectsDir.appendingPathComponent("ttt.md"), id: "tttttttttttttttttttttttttttttttttttttttttttttttttttttttttttt",
                        type: "concept", title: "타겟")
        try writeObject(at: objectsDir.appendingPathComponent("src.md"), id: "ssssssssssssssssssssssssssssssssssssssssssssssssssssssssssss",
                        type: "evidence", title: "소스", body: "[[타겟]]")

        let g = WikiLedgerIndex.buildGraph(root: dir)
        // 소스(src) 가 타겟(ttt) 을 wikilink 로 가리킨다 → ttt in-degree 1, src in-degree 0
        XCTAssertEqual(g.orphans().map(\.id).sorted(), ["ssssssssssssssssssssssssssssssssssssssssssssssssssssssssssss"])
        XCTAssertEqual(g.inDegree(of: "tttttttttttttttttttttttttttttttttttttttttttttttttttttttttttt"), 1)
    }

    // MARK: - 캐시 왕복 (app Core)

    func testIndexCacheRoundtrip() {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("awg-cache-\(UUID().uuidString)")
        let url = dir.appendingPathComponent("index.json")
        let nodes = [node("a", "A")]
        let snap = IndexCache.Snapshot(
            version: IndexCache.currentVersion, ledgerFingerprint: "fp",
            nodes: nodes, edges: [WikiEdge(from: "a", to: "b", kind: .cite)],
            nodeCount: 1, edgeCount: 1, orphanCount: 0, indexedAt: Date()
        )
        IndexCache.save(url: url, snap)
        let loaded = IndexCache.load(url: url)
        XCTAssertEqual(loaded?.ledgerFingerprint, "fp")
        XCTAssertEqual(loaded?.nodeCount, 1)
    }

    // MARK: - 도우미

    private func node(_ id: String, _ title: String) -> WikiNode {
        WikiNode(id: id, type: "evidence", author: "test", published: "", title: title, path: "")
    }

    private func writeObject(at url: URL, id: String, type: String, title: String, body: String = "") throws {
        let md = """
        ---
        id: \(id)
        type: \(type)
        title: \(title)
        author: test
        published: 2026-08-09T00:00:00.000Z
        ---

        \(body)
        """
        try md.write(to: url, atomically: true, encoding: .utf8)
    }
}
