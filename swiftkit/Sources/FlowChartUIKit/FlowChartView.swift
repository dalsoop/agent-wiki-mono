import SwiftUI

/// SwiftUI `Canvas` 및 `TimelineView` 기반의 60fps 즉시 모드(Immediate-Mode) 흐름 다이어그램 렌더러입니다.
/// 노드, 베지어 곡선 간선, 실시간 흐르는 파티클, 펄스 애니메이션을 고성능으로 표현합니다.
public struct FlowChartView: View {
    public let nodes: [FlowNode]
    public let edges: [FlowEdge]
    public var selectedNodeId: String?
    public var onSelectNode: ((String) -> Void)?

    @State private var hoverNodeId: String?

    public init(
        nodes: [FlowNode],
        edges: [FlowEdge],
        selectedNodeId: String? = nil,
        onSelectNode: ((String) -> Void)? = nil
    ) {
        self.nodes = nodes
        self.edges = edges
        self.selectedNodeId = selectedNodeId
        self.onSelectNode = onSelectNode
    }

    public var body: some View {
        TimelineView(.animation) { timeline in
            let currentTime = timeline.date.timeIntervalSinceReferenceDate

            Canvas { context, size in
                let nodeMap = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })

                // 1. 간선(Edges) 및 흐르는 파티클(Particles) 렌더링
                renderEdgesAndParticles(
                    context: context,
                    currentTime: currentTime,
                    nodeMap: nodeMap
                )

                // 2. 노드(Nodes) 렌더링
                renderNodes(
                    context: context,
                    currentTime: currentTime
                )
            }
            .gesture(
                SpatialTapGesture()
                    .onEnded { value in
                        if let hitNode = findNode(at: value.location) {
                            onSelectNode?(hitNode.id)
                        }
                    }
            )
        }
    }

    // MARK: - Edge & Particle Rendering

    private func renderEdgesAndParticles(
        context: GraphicsContext,
        currentTime: TimeInterval,
        nodeMap: [String: FlowNode]
    ) {
        for edge in edges {
            guard let source = nodeMap[edge.sourceId],
                  let target = nodeMap[edge.targetId] else {
                continue
            }

            let start = source.coordinate
            let end = target.coordinate
            let (p1, p2) = FlowParticle.cubicBezierControlPoints(from: start, to: end)

            // 베지어 곡선 경로 생성
            var path = Path()
            path.move(to: start)
            path.addCurve(to: end, control1: p1, control2: p2)

            // 베지어 선 스트로크
            context.stroke(
                path,
                with: .color(edge.color),
                style: StrokeStyle(lineWidth: CGFloat(edge.bandwidth), lineCap: .round, lineJoin: .round)
            )

            // 방향성 화살표 그리기 (타깃 노드 표면 부근)
            drawArrowHead(
                context: context,
                edge: edge,
                p0: start,
                p1: p1,
                p2: p2,
                p3: end,
                targetRadius: target.radius
            )

            // 흐르는 파티클 렌더링
            if edge.flowRate > 0.001 {
                drawParticles(
                    context: context,
                    edge: edge,
                    currentTime: currentTime,
                    p0: start,
                    p1: p1,
                    p2: p2,
                    p3: end
                )
            }
        }
    }

    private func drawArrowHead(
        context: GraphicsContext,
        edge: FlowEdge,
        p0: CGPoint,
        p1: CGPoint,
        p2: CGPoint,
        p3: CGPoint,
        targetRadius: CGFloat
    ) {
        let t: CGFloat = 0.92
        let point = FlowParticle.pointOnCubicBezier(p0: p0, p1: p1, p2: p2, p3: p3, t: t)
        let deltaPoint = FlowParticle.pointOnCubicBezier(p0: p0, p1: p1, p2: p2, p3: p3, t: 0.95)

        let angle = atan2(deltaPoint.y - point.y, deltaPoint.x - point.x)
        let arrowSize: CGFloat = max(6.0, CGFloat(edge.bandwidth) * 2.5)

        var arrowPath = Path()
        let tip = deltaPoint
        let leftWing = CGPoint(
            x: tip.x - arrowSize * cos(angle - .pi / 6.0),
            y: tip.y - arrowSize * sin(angle - .pi / 6.0)
        )
        let rightWing = CGPoint(
            x: tip.x - arrowSize * cos(angle + .pi / 6.0),
            y: tip.y - arrowSize * sin(angle + .pi / 6.0)
        )

        arrowPath.move(to: tip)
        arrowPath.addLine(to: leftWing)
        arrowPath.addLine(to: rightWing)
        arrowPath.closeSubpath()

        context.fill(arrowPath, with: .color(edge.color))
    }

    private func drawParticles(
        context: GraphicsContext,
        edge: FlowEdge,
        currentTime: TimeInterval,
        p0: CGPoint,
        p1: CGPoint,
        p2: CGPoint,
        p3: CGPoint
    ) {
        let count = max(1, edge.particleCount)
        let speed = edge.flowRate
        let basePhase = (currentTime * speed).truncatingRemainder(dividingBy: 1.0)

        for i in 0..<count {
            let offset = Double(i) / Double(count)
            let rawProgress = (basePhase + offset).truncatingRemainder(dividingBy: 1.0)
            let progress = rawProgress < 0 ? rawProgress + 1.0 : rawProgress

            drawSingleParticle(context: context, edge: edge, p0: p0, p1: p1, p2: p2, p3: p3, progress: progress)

            if edge.isBidirectional {
                let reverseProgress = 1.0 - progress
                drawSingleParticle(context: context, edge: edge, p0: p0, p1: p1, p2: p2, p3: p3, progress: reverseProgress, isReverse: true)
            }
        }
    }

    private func drawSingleParticle(
        context: GraphicsContext,
        edge: FlowEdge,
        p0: CGPoint,
        p1: CGPoint,
        p2: CGPoint,
        p3: CGPoint,
        progress: Double,
        isReverse: Bool = false
    ) {
        let pos = FlowParticle.pointOnCubicBezier(p0: p0, p1: p1, p2: p2, p3: p3, t: CGFloat(progress))
        let radius = max(2.5, CGFloat(edge.bandwidth) * 1.2)

        if !isReverse {
            let glowRect = CGRect(x: pos.x - radius * 1.8, y: pos.y - radius * 1.8, width: radius * 3.6, height: radius * 3.6)
            context.fill(Circle().path(in: glowRect), with: .color(edge.color.opacity(0.4)))
        }

        let coreRect = CGRect(x: pos.x - radius, y: pos.y - radius, width: radius * 2.0, height: radius * 2.0)
        let color: Color = isReverse ? edge.color.opacity(0.85) : .white
        context.fill(Circle().path(in: coreRect), with: .color(color))
    }

    // MARK: - Node Rendering

    private func renderNodes(
        context: GraphicsContext,
        currentTime: TimeInterval
    ) {
        for node in nodes {
            renderSingleNode(context: context, node: node, currentTime: currentTime)
        }
    }

    private func renderSingleNode(
        context: GraphicsContext,
        node: FlowNode,
        currentTime: TimeInterval
    ) {
        let center = node.coordinate
        let radius = node.radius

        drawPulseIfPulsing(context: context, node: node, currentTime: currentTime)
        drawHighlightIfSelected(context: context, node: node)

        // 노드 본체 배경
        let nodeRect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2.0, height: radius * 2.0)
        context.fill(Circle().path(in: nodeRect), with: .color(node.statusColor))
        context.stroke(Circle().path(in: nodeRect), with: .color(Color.white.opacity(0.8)), lineWidth: 1.5)

        // 노드 라벨 텍스트
        let labelText = Text(node.label)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundColor(.white)
        context.draw(labelText, at: center)

        drawNodeBadgeIfPresent(context: context, node: node)
    }

    private func drawPulseIfPulsing(context: GraphicsContext, node: FlowNode, currentTime: TimeInterval) {
        guard node.isPulsing else { return }
        let pulsePeriod = 1.2
        let phase = (currentTime / pulsePeriod).truncatingRemainder(dividingBy: 1.0)
        let pulseRadius = node.radius + CGFloat(phase) * 18.0
        let pulseOpacity = (1.0 - phase) * 0.6
        let pulseRect = CGRect(
            x: node.coordinate.x - pulseRadius,
            y: node.coordinate.y - pulseRadius,
            width: pulseRadius * 2.0,
            height: pulseRadius * 2.0
        )
        context.stroke(Circle().path(in: pulseRect), with: .color(node.statusColor.opacity(pulseOpacity)), lineWidth: 2.0)
    }

    private func drawHighlightIfSelected(context: GraphicsContext, node: FlowNode) {
        guard node.id == selectedNodeId else { return }
        let highlightRadius = node.radius + 6.0
        let highlightRect = CGRect(
            x: node.coordinate.x - highlightRadius,
            y: node.coordinate.y - highlightRadius,
            width: highlightRadius * 2.0,
            height: highlightRadius * 2.0
        )
        context.stroke(Circle().path(in: highlightRect), with: .color(.white), lineWidth: 2.5)
    }

    private func drawNodeBadgeIfPresent(context: GraphicsContext, node: FlowNode) {
        guard let badge = node.badge, !badge.isEmpty else { return }
        let badgePoint = CGPoint(x: node.coordinate.x + node.radius * 0.7, y: node.coordinate.y - node.radius * 0.7)
        let badgeBgRect = CGRect(x: badgePoint.x - 10.0, y: badgePoint.y - 7.0, width: 20.0, height: 14.0)
        context.fill(Capsule().path(in: badgeBgRect), with: .color(Color.black.opacity(0.75)))
        let badgeText = Text(badge)
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(.white)
        context.draw(badgeText, at: badgePoint)
    }

    // MARK: - Hit Testing

    private func findNode(at location: CGPoint) -> FlowNode? {
        nodes.first { node in
            let dx = node.coordinate.x - location.x
            let dy = node.coordinate.y - location.y
            let dist = hypot(dx, dy)
            return dist <= (node.radius + 6.0)
        }
    }
}
