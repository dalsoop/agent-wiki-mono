import KnowledgeBaseWikiCore
import SwiftUI

/// 저장 3층 배선도 — 목록이 아니라 **그림**.
///
/// 같은 수치를 표로도 낼 수 있지만, 이 화면이 답해야 하는 질문이 "어느 층과 어느 층
/// 사이가 끊겼나"라서 그렇다. 표는 행을 읽고 머릿속에서 배선을 조립하게 만들고,
/// 그림은 끊긴 화살표를 바로 가리킨다 — 오늘 발견된 결함들이 전부 "층은 멀쩡한데
/// 층 사이가 끊긴" 형태였다(원문은 봉인됐는데 검색이 못 닿음, gc 가 산 원본을 회수
/// 대상으로 봄).
///
/// 좌표는 층(y) × 순서(x) 고정 격자다. 간선은 실측 상태에 따라 색·점선이 바뀐다.
struct StructureDiagram: View {
    let structure: LedgerStructure
    /// 간선을 누르면 상세로 — 그림에서 바로 문제로 들어간다.
    var onSelect: (LedgerStructure.Edge) -> Void = { _ in }

    /// 배치는 Core 가 계산한다(순수 함수 → 테스트 가능). 여기서는 그리기만 한다.
    private var layout: StructureLayout { StructureLayout(structure: structure) }
    private var size: CGSize {
        let s = layout.size
        return CGSize(width: s.width, height: s.height)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in draw(in: &context) }
                .frame(width: size.width, height: size.height)
            // 간선 히트영역 — Canvas 는 클릭을 안 받으므로 투명 버튼을 겹친다.
            ForEach(layout.wires, id: \.edgeID) { wire in
                if let edge = edge(wire.edgeID) {
                    Button { onSelect(edge) } label: {
                        Color.clear.frame(width: 150, height: 26)
                    }
                    .buttonStyle(.plain)
                    .position(x: wire.label.x, y: wire.label.y)
                    .help("\(edge.label) — \(edge.note)")
                    .accessibilityLabel("\(edge.label) \(statusWord(edge)) \(countText(edge))")
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .padding(.vertical, 6)
    }

    // MARK: - 그리기

    private func edge(_ id: String) -> LedgerStructure.Edge? {
        structure.edges.first { $0.id == id }
    }

    private func cg(_ r: StructureLayout.Rect) -> CGRect {
        CGRect(x: r.x, y: r.y, width: r.width, height: r.height)
    }

    private func cg(_ p: StructureLayout.Point) -> CGPoint { CGPoint(x: p.x, y: p.y) }

    /// 층 색 — 봉인(갈색) · 해석(청록) · 파생(주황). 신뢰 등급이 곧 색이다.
    private func tint(_ tier: StructureLayout.Tier) -> Color {
        switch tier {
        case .seal: .brown
        case .interpretation: .teal
        case .derived: .orange
        }
    }

    private func draw(in context: inout GraphicsContext) {
        for wire in layout.wires { drawWire(wire, in: &context) }
        for b in layout.boxes { drawBox(b, in: &context) }
    }

    private func drawBox(_ b: StructureLayout.Box, in context: inout GraphicsContext) {
        let rect = cg(b.rect)
        let color = tint(b.tier)
        let path = Path(roundedRect: rect, cornerRadius: 5)
        context.fill(path, with: .color(color.opacity(0.10)))
        context.stroke(path, with: .color(color.opacity(0.75)), lineWidth: 1.4)
        context.draw(
            Text(b.title).font(.system(size: 12, weight: .semibold, design: .monospaced)),
            at: CGPoint(x: rect.minX + 12, y: rect.minY + 20), anchor: .leading)
        context.draw(
            Text(b.subtitle).font(.system(size: 10.5)).foregroundStyle(.secondary),
            at: CGPoint(x: rect.minX + 12, y: rect.minY + 40), anchor: .leading)
    }

    private func drawWire(_ wire: StructureLayout.Wire, in context: inout GraphicsContext) {
        guard let edge = edge(wire.edgeID) else { return }
        let color = tint(edge)
        let start = cg(wire.from), end = cg(wire.to), mid = cg(wire.label)
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        let dash: [CGFloat] = edge.contract == .informational ? [3, 3] : []
        context.stroke(path, with: .color(color),
                       style: StrokeStyle(lineWidth: edge.contract == .invariant ? 2 : 1.4,
                                          dash: dash))
        drawArrowHead(at: end, from: start, color: color, in: &context)

        // 간선 라벨 — 배경을 깔아 선 위에서도 읽히게.
        let label = "\(edge.label)  \(countText(edge))"
        let resolved = context.resolve(
            Text(label).font(.system(size: 10.5, weight: .medium)).foregroundStyle(color))
        let textSize = resolved.measure(in: CGSize(width: 260, height: 40))
        let padded = CGRect(x: mid.x - textSize.width / 2 - 4,
                            y: mid.y - textSize.height / 2 - 2,
                            width: textSize.width + 8, height: textSize.height + 4)
        context.fill(Path(roundedRect: padded, cornerRadius: 3),
                     with: .color(Color(nsColor: .windowBackgroundColor).opacity(0.92)))
        context.draw(resolved, at: mid, anchor: .center)
    }

    private func drawArrowHead(
        at point: CGPoint, from origin: CGPoint, color: Color, in context: inout GraphicsContext
    ) {
        let angle = atan2(point.y - origin.y, point.x - origin.x)
        let length: CGFloat = 8, spread: CGFloat = .pi / 7
        var head = Path()
        head.move(to: point)
        head.addLine(to: CGPoint(x: point.x - length * cos(angle - spread),
                                 y: point.y - length * sin(angle - spread)))
        head.addLine(to: CGPoint(x: point.x - length * cos(angle + spread),
                                 y: point.y - length * sin(angle + spread)))
        head.closeSubpath()
        context.fill(head, with: .color(color))
    }

    // MARK: - 표현

    private func tint(_ edge: LedgerStructure.Edge) -> Color {
        switch edge.status {
        case .satisfied: return edge.contract == .informational ? .secondary : .green
        case .partial: return edge.contract == .invariant ? .red : .orange
        case .missing: return edge.contract == .informational ? .secondary : .red
        }
    }

    private func countText(_ edge: LedgerStructure.Edge) -> String {
        edge.total == 1 ? (edge.actual == 1 ? "OK" : "미달") : "\(edge.actual)/\(edge.total)"
    }

    private func statusWord(_ edge: LedgerStructure.Edge) -> String {
        switch edge.status {
        case .satisfied: "충족"
        case .partial: "부분"
        case .missing: "미연결"
        }
    }

}
