import XCTest
import SwiftUI
@testable import FlowChartUIKit

final class FlowChartTests: XCTestCase {

    func testFlowNodeInitializationAndDefaults() {
        let node = FlowNode(
            id: "node-1",
            label: "Node 1",
            coordinate: CGPoint(x: 100, y: 150)
        )

        XCTAssertEqual(node.id, "node-1")
        XCTAssertEqual(node.label, "Node 1")
        XCTAssertEqual(node.coordinate.x, 100)
        XCTAssertEqual(node.coordinate.y, 150)
        XCTAssertEqual(node.statusColor, .blue)
        XCTAssertNil(node.badge)
        XCTAssertFalse(node.isPulsing)
        XCTAssertEqual(node.radius, 26.0)
    }

    func testFlowNodeCustomProperties() {
        let node = FlowNode(
            id: "node-custom",
            label: "Custom Node",
            coordinate: CGPoint(x: 200, y: 300),
            statusColor: .green,
            badge: "HOT",
            isPulsing: true,
            radius: 32.0,
            subtitle: "Sub"
        )

        XCTAssertEqual(node.id, "node-custom")
        XCTAssertEqual(node.statusColor, .green)
        XCTAssertEqual(node.badge, "HOT")
        XCTAssertTrue(node.isPulsing)
        XCTAssertEqual(node.radius, 32.0)
        XCTAssertEqual(node.subtitle, "Sub")
    }

    func testFlowEdgeInitialization() {
        let edge = FlowEdge(
            id: "edge-1",
            sourceId: "node-1",
            targetId: "node-2",
            bandwidth: 3.5,
            flowRate: 0.8,
            color: .purple,
            isBidirectional: true,
            particleCount: 5,
            label: "Connection"
        )

        XCTAssertEqual(edge.id, "edge-1")
        XCTAssertEqual(edge.sourceId, "node-1")
        XCTAssertEqual(edge.targetId, "node-2")
        XCTAssertEqual(edge.bandwidth, 3.5)
        XCTAssertEqual(edge.flowRate, 0.8)
        XCTAssertEqual(edge.color, .purple)
        XCTAssertTrue(edge.isBidirectional)
        XCTAssertEqual(edge.particleCount, 5)
        XCTAssertEqual(edge.label, "Connection")
    }

    func testCubicBezierPointInterpolation() {
        let p0 = CGPoint(x: 0, y: 0)
        let p1 = CGPoint(x: 0, y: 100)
        let p2 = CGPoint(x: 100, y: 100)
        let p3 = CGPoint(x: 100, y: 0)

        let startPoint = FlowParticle.pointOnCubicBezier(p0: p0, p1: p1, p2: p2, p3: p3, t: 0.0)
        XCTAssertEqual(startPoint.x, 0.0, accuracy: 0.001)
        XCTAssertEqual(startPoint.y, 0.0, accuracy: 0.001)

        let endPoint = FlowParticle.pointOnCubicBezier(p0: p0, p1: p1, p2: p2, p3: p3, t: 1.0)
        XCTAssertEqual(endPoint.x, 100.0, accuracy: 0.001)
        XCTAssertEqual(endPoint.y, 0.0, accuracy: 0.001)

        let midPoint = FlowParticle.pointOnCubicBezier(p0: p0, p1: p1, p2: p2, p3: p3, t: 0.5)
        XCTAssertEqual(midPoint.x, 50.0, accuracy: 0.001)
        XCTAssertEqual(midPoint.y, 75.0, accuracy: 0.001)
    }

    func testCubicBezierControlPointsGeneration() {
        let start = CGPoint(x: 10, y: 20)
        let end = CGPoint(x: 110, y: 20)

        let (cp1, cp2) = FlowParticle.cubicBezierControlPoints(from: start, to: end)
        XCTAssertGreaterThan(cp1.x, start.x)
        XCTAssertLessThan(cp2.x, end.x)
        XCTAssertEqual(cp1.y, start.y)
        XCTAssertEqual(cp2.y, end.y)
    }

    @MainActor
    func testFlowChartViewInitialization() {
        let node1 = FlowNode(id: "n1", label: "A", coordinate: CGPoint(x: 50, y: 50))
        let node2 = FlowNode(id: "n2", label: "B", coordinate: CGPoint(x: 150, y: 50))
        let edge = FlowEdge(id: "e1", sourceId: "n1", targetId: "n2")

        let view = FlowChartView(
            nodes: [node1, node2],
            edges: [edge],
            selectedNodeId: "n1"
        )

        XCTAssertEqual(view.nodes.count, 2)
        XCTAssertEqual(view.edges.count, 1)
        XCTAssertEqual(view.selectedNodeId, "n1")
    }
}
