import Foundation
import Testing
@testable import WikiLedgerKit

/// 그래프 파서(grapher)가 ledger 3 파일을 노드·간선으로 싣는지 — 파서 정본은 `LawRecordParser`.
@Suite("그래프 파서의 ledger 3 노드")
struct LedgerThreeGraphParserTests {
    static let target = String(repeating: "a", count: 64)
    static let previous = String(repeating: "b", count: 64)
    static let merged = String(repeating: "c", count: 64)

    static func record() -> LawRecord {
        LawRecord(
            promulgated: LawTime.parse("2026-10-04T01:02:03.456Z")!,
            author: "agent:claude@macbook", authorKind: "agent", device: "macbook",
            runtime: "claude-code", model: "claude-opus-5-5", effort: "high", speaker: "agent",
            title: "개정된 기록", type: "record", batch: "batch-1",
            cites: [LawCite(id: target, rel: "cites"), LawCite(id: target, rel: "testifies")],
            amends: previous, amendsAlso: [merged], body: "본문 [[다른 기록]]\n")
    }

    @Test("ledger 3 파일 → 노드(공포일·유형·작성자)와 간선(cites 관계·amends·batch·wikilink)")
    func ledgerThreeNode() throws {
        let record = Self.record()
        let id = record.contentID()
        let parsed = try #require(WikiLedgerParser.parse(raw: record.serialize(id: id), relativePath: "objects/2026/10/x.md"))
        #expect(parsed.node.id == id)
        #expect(parsed.node.type == "record")
        #expect(parsed.node.author == "agent:claude@macbook")
        #expect(parsed.node.published == "2026-10-04T01:02:03.456Z")
        #expect(parsed.node.title == "개정된 기록")
        let cites = parsed.edges.filter { $0.kind == WikiEdgeKind.cite.rawValue }
        #expect(cites.map(\.relation) == ["cites", "testifies"])
        let supersedes = parsed.edges.filter { $0.kind == WikiEdgeKind.supersedes.rawValue }.map(\.to)
        #expect(supersedes == [Self.previous, Self.merged])
        #expect(parsed.edges.contains { $0.kind == WikiEdgeKind.batch.rawValue && $0.to == "batch-1" })
        #expect(parsed.edges.contains { $0.kind == WikiEdgeKind.wikilink.rawValue && $0.to == "다른 기록" })
    }

    @Test("폐지 기록 → retracts 간선")
    func repealEdge() throws {
        let record = LawRecord(
            promulgated: LawTime.parse("2026-10-04T01:02:03.456Z")!, author: "user:jeonghan",
            authorKind: "human", runtime: "human", speaker: "user", title: "폐지: x", type: "record",
            repeals: Self.target, body: "")
        let parsed = try #require(WikiLedgerParser.parse(raw: record.serialize(id: record.contentID()), relativePath: "x.md"))
        #expect(parsed.edges.contains { $0.kind == WikiEdgeKind.retracts.rawValue && $0.to == Self.target })
    }

    @Test("ledger 2 파일은 옛 경로 그대로")
    func ledgerTwoUnchanged() throws {
        let raw = """
            ---
            ledger: 2
            id: \(Self.target)
            published: 2026-01-01T00:00:00Z
            author: agent:a
            sha256: x
            title: 결정: y
            cite: \(Self.previous) supports
            ---
            본문
            """
        let parsed = try #require(WikiLedgerParser.parse(raw: raw, relativePath: "x.md"))
        #expect(parsed.node.type == "decision")
        #expect(parsed.node.published == "2026-01-01T00:00:00Z")
        #expect(parsed.edges.contains { $0.kind == "cite" && $0.relation == "supports" })
    }
}
