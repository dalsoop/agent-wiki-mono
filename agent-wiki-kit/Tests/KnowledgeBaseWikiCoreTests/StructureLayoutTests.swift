import Foundation
import Testing

@testable import KnowledgeBaseWikiCore

/// 배선도 배치 계약 — 그림이 읽히는지를 **기하로** 검증한다.
///
/// 스크린샷으로 확인하려 했지만 이 Mac 에서는 다른 에이전트 세션 창이 계속 앞으로
/// 올라와 창 캡처가 세 번 연속 다른 앱을 찍었다(2026-08-04). 배치를 순수 함수로
/// 빼두면 화면 없이도 "상자가 겹치나 · 화살표가 테두리에 닿나 · 끝점이 상자 안으로
/// 파고들지 않나"를 못 박을 수 있고, 회귀도 잡힌다.
@Suite struct StructureLayoutTests {
    private func makeStructure() -> LedgerStructure {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("kbw-layout-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LedgerStore(root: root)
        _ = try? store.publish(author: "test", title: "근거: 배치", type: "evidence", body: "본문")
        _ = try? BlobStore(root: root).put(Data("원문".utf8))
        return LedgerStructure(root: root)
    }

    /// 상자끼리 겹치지 않는다 — 겹치면 라벨이 서로를 가린다.
    @Test func boxesDoNotOverlap() {
        let layout = StructureLayout(structure: makeStructure())
        #expect(layout.boxes.count >= 5)
        for (i, a) in layout.boxes.enumerated() {
            for b in layout.boxes[(i + 1)...] {
                #expect(!a.rect.intersects(b.rect), "\(a.id) 와 \(b.id) 가 겹친다")
            }
        }
    }

    /// 층은 위에서 아래로 봉인 → 해석 → 파생 순서로 내려간다(신뢰의 방향).
    @Test func tiersDescendInTrustOrder() {
        let layout = StructureLayout(structure: makeStructure())
        func topY(_ tier: StructureLayout.Tier) -> Double? {
            layout.boxes.filter { $0.tier == tier }.map(\.rect.y).min()
        }
        let seal = try? #require(topY(.seal))
        let interpretation = try? #require(topY(.interpretation))
        let derived = try? #require(topY(.derived))
        #expect((seal ?? 0) < (interpretation ?? 0))
        #expect((interpretation ?? 0) < (derived ?? 0))
        // 같은 층의 상자는 같은 y 에 정렬된다 — 어긋난 baseline 은 노이즈로 읽힌다.
        for tier in [StructureLayout.Tier.seal, .interpretation, .derived] {
            let ys = Set(layout.boxes.filter { $0.tier == tier }.map(\.rect.y))
            #expect(ys.count <= 1, "\(tier) 층의 baseline 이 어긋났다")
        }
    }

    /// 화살표 끝점은 상자 **테두리 위**다 — 안으로 파고들면 화살촉이 가려진다.
    @Test func wireEndpointsSitOnBoxEdges() {
        let structure = makeStructure()
        let layout = StructureLayout(structure: structure)
        #expect(!layout.wires.isEmpty)
        for wire in layout.wires {
            let onSomeEdge = layout.boxes.contains { box in
                box.rect.contains(wire.from) || box.rect.contains(wire.to)
            }
            #expect(onSomeEdge, "\(wire.edgeID) 끝점이 어느 상자에도 안 붙는다")
            // 끝점이 상자 **내부 깊숙이** 있으면 안 된다(테두리 근방이어야).
            for box in layout.boxes {
                let deepInside = wire.to.x > box.rect.x + 1 && wire.to.x < box.rect.maxX - 1
                    && wire.to.y > box.rect.y + 1 && wire.to.y < box.rect.maxY - 1
                #expect(!deepInside, "\(wire.edgeID) 끝점이 \(box.id) 안으로 파고들었다")
            }
        }
    }

    /// 모든 간선이 배치된다 — 끝점 이름이 상자와 안 맞으면 그림에서 조용히 사라진다.
    @Test func everyEdgeIsPlaced() {
        let structure = makeStructure()
        let layout = StructureLayout(structure: structure)
        let placed = Set(layout.wires.map(\.edgeID))
        for edge in structure.edges {
            #expect(placed.contains(edge.id), "\(edge.id) 가 그림에서 빠졌다 — 끝점 이름 확인")
        }
    }

    /// 캔버스가 모든 상자를 담는다.
    @Test func canvasContainsEveryBox() {
        let layout = StructureLayout(structure: makeStructure())
        for box in layout.boxes {
            #expect(box.rect.maxX <= layout.size.width)
            #expect(box.rect.maxY <= layout.size.height)
        }
    }
}
