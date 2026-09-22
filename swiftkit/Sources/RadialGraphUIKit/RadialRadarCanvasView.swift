import SwiftUI

/// 4단 동심원 레이더 캔버스 뷰 (순수 기하 뷰)
public struct RadialRadarCanvasView: View {
    public let focusNode: RadialNode?
    public let nodes: [RadialNode]
    @Binding public var selectedNodeID: String?
    public var onSelectNode: ((RadialNode) -> Void)?

    @State private var hoveredNodeID: String?

    public init(
        focusNode: RadialNode? = nil,
        nodes: [RadialNode],
        selectedNodeID: Binding<String?> = .constant(nil),
        onSelectNode: ((RadialNode) -> Void)? = nil
    ) {
        self.focusNode = focusNode
        self.nodes = nodes
        self._selectedNodeID = selectedNodeID
        self.onSelectNode = onSelectNode
    }

    public var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let maxRadius = (size / 2) - 28.0

            ZStack {
                // 1. 동심원 4단 링
                ForEach(1...4, id: \.self) { ringIndex in
                    let ringRadius = maxRadius * (Double(ringIndex) / 4.0)
                    Circle()
                        .stroke(
                            ringColor(for: ringIndex),
                            style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                        )
                        .frame(width: ringRadius * 2, height: ringRadius * 2)
                        .position(center)
                }

                // 2. 중심 관점 노드 (Focus Node)
                if let focus = focusNode {
                    RadialBubbleView(
                        node: focus,
                        isSelected: selectedNodeID == focus.id,
                        isHovered: hoveredNodeID == focus.id,
                        isCenter: true
                    )
                    .position(center)
                    .onTapGesture {
                        selectedNodeID = focus.id
                        onSelectNode?(focus)
                    }
                }

                // 3. 주변 노드 (티어별 각도 자동 분산)
                let positionedNodes = calculatePositions(in: nodes, center: center, maxRadius: maxRadius)
                ForEach(positionedNodes, id: \.node.id) { item in
                    RadialBubbleView(
                        node: item.node,
                        isSelected: selectedNodeID == item.node.id,
                        isHovered: hoveredNodeID == item.node.id,
                        isCenter: false
                    )
                    .position(item.position)
                    .onHover { hovering in
                        hoveredNodeID = hovering ? item.node.id : nil
                    }
                    .onTapGesture {
                        selectedNodeID = item.node.id
                        onSelectNode?(item.node)
                    }
                }
            }
        }
    }

    private func ringColor(for index: Int) -> Color {
        switch index {
        case 1: return Color.accentColor.opacity(0.35)
        case 2: return Color.primary.opacity(0.20)
        case 3: return Color.primary.opacity(0.15)
        default: return Color.primary.opacity(0.10)
        }
    }

    /// 티어별 및 거리별 노드 충돌 방지 각도 자동 분산 알고리즘
    private func calculatePositions(
        in nodes: [RadialNode],
        center: CGPoint,
        maxRadius: Double
    ) -> [(node: RadialNode, position: CGPoint)] {
        guard !nodes.isEmpty else { return [] }

        // 티어별로 그룹화하여 각 티어 내에서 균등 각도 분산
        let grouped = Dictionary(grouping: nodes, by: \.tier)
        var result: [(node: RadialNode, position: CGPoint)] = []

        for (tier, tierNodes) in grouped {
            let count = tierNodes.count
            let angleStep = (2.0 * Double.pi) / Double(count)
            // 티어마다 시작 위상을 조금씩 틀어 겹침 방지
            let tierOffset = Double(tier.rawValue) * (Double.pi / 5.0)

            for (i, node) in tierNodes.enumerated() {
                let angle = tierOffset + (Double(i) * angleStep)
                // 거리 0.05 ~ 0.95 클램프 (중심 노드와 겹치지 않도록 최소 반지름 보장)
                let clampedDist = max(node.distance, 0.12)
                let radius = maxRadius * clampedDist

                let x = center.x + CGFloat(cos(angle) * radius)
                let y = center.y + CGFloat(sin(angle) * radius)
                result.append((node: node, position: CGPoint(x: x, y: y)))
            }
        }

        return result
    }
}

/// 방사형 노드 버블 뷰 (호버 및 선택 효과 지원)
public struct RadialBubbleView: View {
    public let node: RadialNode
    public let isSelected: Bool
    public let isHovered: Bool
    public let isCenter: Bool

    public init(
        node: RadialNode,
        isSelected: Bool = false,
        isHovered: Bool = false,
        isCenter: Bool = false
    ) {
        self.node = node
        self.isSelected = isSelected
        self.isHovered = isHovered
        self.isCenter = isCenter
    }

    public var body: some View {
        VStack(spacing: 3) {
            ZStack {
                let bubbleColor = node.tintHex.flatMap(Color.init(hex:)) ?? (isCenter ? Color.accentColor : Color.secondary.opacity(0.2))
                
                if node.shape == .circle {
                    Circle()
                        .fill(bubbleColor)
                        .frame(width: node.size, height: node.size)
                        .overlay(
                            Circle()
                                .stroke(isSelected ? Color.accentColor : (isHovered ? Color.primary.opacity(0.5) : Color.clear), lineWidth: 2)
                        )
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(bubbleColor)
                        .frame(width: node.size, height: node.size)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isSelected ? Color.accentColor : (isHovered ? Color.primary.opacity(0.5) : Color.clear), lineWidth: 2)
                        )
                }

                if let icon = node.iconSystemName {
                    Image(systemName: icon)
                        .font(.system(size: node.size * 0.45, weight: .semibold))
                        .foregroundColor(.primary)
                }
            }
            .scaleEffect(isHovered ? 1.15 : (isSelected ? 1.1 : 1.0))
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovered)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSelected)

            Text(node.label)
                .font(.system(size: 10, weight: isCenter ? .bold : .medium))
                .lineLimit(1)
                .foregroundColor(isSelected ? .primary : .secondary)
        }
        .frame(width: max(node.size * 2, 60))
    }
}

private extension Color {
    struct RGBA {
        var a: UInt64
        var r: UInt64
        var g: UInt64
        var b: UInt64
    }

    init?(hex: String) {
        let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        guard Scanner(string: clean).scanHexInt64(&int) else { return nil }
        let rgba: RGBA
        switch clean.count {
        case 3: // RGB (12-bit)
            rgba = RGBA(a: 255, r: (int >> 8) * 17, g: (int >> 4 & 0xF) * 17, b: (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            rgba = RGBA(a: 255, r: int >> 16, g: int >> 8 & 0xFF, b: int & 0xFF)
        case 8: // ARGB (32-bit)
            rgba = RGBA(a: int >> 24, r: int >> 16 & 0xFF, g: int >> 8 & 0xFF, b: int & 0xFF)
        default:
            return nil
        }
        self.init(
            .sRGB,
            red: Double(rgba.r) / 255,
            green: Double(rgba.g) / 255,
            blue: Double(rgba.b) / 255,
            opacity: Double(rgba.a) / 255
        )
    }
}
