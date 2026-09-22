import CoreGraphics
import XCTest
@testable import GraphLayoutKit

final class GraphLayoutKitTests: XCTestCase {

    private func makeGraph(count: Int) -> (nodes: [LayoutNode], edges: [LayoutEdge]) {
        let nodes = (0..<count).map { LayoutNode(id: "n\(String(format: "%03d", $0))") }
        var edges: [LayoutEdge] = []
        for i in 0..<count {
            // 체인 + 몇몇 크로스 링크 — 클러스터가 생기게.
            if i + 1 < count { edges.append(LayoutEdge(from: nodes[i].id, to: nodes[i + 1].id)) }
            if i % 5 == 0, i + 3 < count { edges.append(LayoutEdge(from: nodes[i].id, to: nodes[i + 3].id, weight: 0.5)) }
        }
        return (nodes, edges)
    }

    /// 결정론: 같은 입력으로 두 번 돌리면 완전히 같은 좌표가 나온다.
    func testDeterministicSameInputSameOutput() {
        let (nodes, edges) = makeGraph(count: 24)
        let size = CGSize(width: 800, height: 600)
        let r1 = ForceDirectedLayout.layout(nodes: nodes, edges: edges, canvasSize: size)
        let r2 = ForceDirectedLayout.layout(nodes: nodes, edges: edges, canvasSize: size)
        XCTAssertEqual(r1.positions.count, nodes.count)
        for node in nodes {
            guard let p1 = r1[node.id], let p2 = r2[node.id] else {
                XCTFail("missing position for \(node.id)"); continue
            }
            XCTAssertEqual(p1.x, p2.x, accuracy: 1e-9)
            XCTAssertEqual(p1.y, p2.y, accuracy: 1e-9)
        }
    }

    /// 결정론은 입력 노드 순서에 의존하지 않는다(내부적으로 id 정렬).
    func testDeterministicRegardlessOfInputOrder() {
        let (nodes, edges) = makeGraph(count: 15)
        let size = CGSize(width: 500, height: 400)
        let shuffled = Array(nodes.reversed())
        let r1 = ForceDirectedLayout.layout(nodes: nodes, edges: edges, canvasSize: size)
        let r2 = ForceDirectedLayout.layout(nodes: shuffled, edges: edges, canvasSize: size)
        for node in nodes {
            XCTAssertEqual(r1[node.id]!.x, r2[node.id]!.x, accuracy: 1e-9)
            XCTAssertEqual(r1[node.id]!.y, r2[node.id]!.y, accuracy: 1e-9)
        }
    }

    /// 경계: 모든 결과 좌표는 주어진 canvas rect 안에 있어야 한다.
    func testAllPositionsWithinCanvasBounds() {
        let (nodes, edges) = makeGraph(count: 60)
        let size = CGSize(width: 640, height: 420)
        let result = ForceDirectedLayout.layout(nodes: nodes, edges: edges, canvasSize: size)
        let rect = CGRect(origin: .zero, size: size)
        for (id, p) in result.positions {
            XCTAssertTrue(rect.contains(p), "\(id) at \(p) outside \(rect)")
        }
    }

    /// 겹침 없음: 합리적 규모 그래프에서 어떤 두 노드도 최소 간격보다 가깝지 않다.
    func testNoOverlapMinimumSeparation() {
        let (nodes, edges) = makeGraph(count: 40)
        let size = CGSize(width: 700, height: 500)
        let config = ForceDirectedLayout.Configuration(minSeparation: 18)
        let result = ForceDirectedLayout.layout(nodes: nodes, edges: edges, canvasSize: size, configuration: config)
        let points = nodes.map { result[$0.id]! }
        for i in 0..<points.count {
            for j in (i + 1)..<points.count {
                let dx = points[i].x - points[j].x
                let dy = points[i].y - points[j].y
                let dist = sqrt(dx * dx + dy * dy)
                XCTAssertGreaterThanOrEqual(
                    dist, CGFloat(config.minSeparation) - 0.5,
                    "nodes \(i),\(j) too close: \(dist)")
            }
        }
    }

    /// 빈 입력·단일 노드 경계 케이스가 크래시하지 않는다.
    func testEmptyAndSingleNode() {
        let size = CGSize(width: 300, height: 200)
        let empty = ForceDirectedLayout.layout(nodes: [], edges: [], canvasSize: size)
        XCTAssertTrue(empty.positions.isEmpty)

        let single = ForceDirectedLayout.layout(nodes: [LayoutNode(id: "solo")], edges: [], canvasSize: size)
        XCTAssertEqual(single.positions.count, 1)
        XCTAssertTrue(CGRect(origin: .zero, size: size).contains(single["solo"]!))
    }

    /// 고정 노드는 시뮬레이션 후에도 지정 위치(클램프 내)에 머무른다.
    func testFixedNodeStaysNearPin() {
        let pin = CGPoint(x: 100, y: 100)
        var nodes = [LayoutNode(id: "pinned", fixedPosition: pin)]
        nodes += (0..<10).map { LayoutNode(id: "free\($0)") }
        let edges = (0..<10).map { LayoutEdge(from: "pinned", to: "free\($0)") }
        let size = CGSize(width: 400, height: 400)
        let result = ForceDirectedLayout.layout(nodes: nodes, edges: edges, canvasSize: size)
        XCTAssertEqual(result["pinned"], pin)
    }
}
