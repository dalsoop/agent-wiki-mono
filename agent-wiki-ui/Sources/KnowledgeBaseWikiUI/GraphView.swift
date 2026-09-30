import Grape
import KnowledgeBaseWikiCore
import SwiftUI

/// 관계도 — 옵시디언식 force 그래프. 시각 어휘는 앱 공통 규약 그대로:
/// 크기=지지도, 투명도=신선도, 초록 선=재현, 빨강 선=반박, 회색 선=참고/인용.
/// supersedes 계보는 노드로 펼치지 않고 head 하나로 접는다(역사는 기록 시트 소관).
struct LedgerGraphView: View {
    @Bindable var model: LedgerModel
    @State private var graphStates = ForceDirectedGraphState(initialIsRunning: true)

    private struct GraphNode: Identifiable {
        let id: String
        let label: String
        let color: Color
        let radius: Double
        let opacity: Double
    }

    private struct GraphEdge: Identifiable {
        let id: String
        let from: String
        let to: String
        let color: Color
        let width: Double
    }

    /// head 문서만 노드로, 인용은 계보의 어느 판을 가리켰든 head 로 승격해 연결.
    private var graphData: (nodes: [GraphNode], edges: [GraphEdge]) {
        guard let store = model.storeForGraph else { return ([], []) }
        let objects = model.objects
        // 지식 head + 해석(분류·반박·이의 …)을 노드로. 나머지 절차 스탬프(선별·run·체크포인트)는
        // 노드가 아니라 지지도·간선으로만 — 섞이면 헤어볼. 해석은 사실↔판단을 잇는 1급이라 포함한다.
        let heads = store.heads(objects).filter {
            $0.retracts == nil && (!$0.isProcess || $0.isInterpretation)
        }
        // 판 id → head id 매핑
        var headOf: [String: String] = [:]
        for head in heads {
            for version in store.lineage(objects, of: head.id) {
                headOf[version.id] = head.id
            }
        }
        var nodes: [GraphNode] = []
        for head in heads {
            let document = LedgerDocument(head: head, versions: store.lineage(objects, of: head.id))
            let strength = store.strength(objects, of: head)
            let isMine = head.author == "human" && head.effectiveType != "evidence"
            let stage = model.stage(of: head)
            let isWiki = head.author == "wiki-maintainer"
            let isEntity = head.effectiveType == "entity"
            let color: Color = head.isInterpretation ? .brown   // 해석(판단) — 경합·버전
                : isEntity ? .cyan
                : isWiki ? .indigo
                : isMine ? .purple
                : stage == .verified ? .green
                : strength.contradictCount > 0 ? .red
                : head.origin?.hasPrefix("http") == true ? .orange : .blue
            nodes.append(GraphNode(
                id: head.id,
                label: document.title.replacingOccurrences(of: "근거: ", with: ""),
                color: color,
                radius: 6 + strength.score * 14,
                opacity: 0.35 + 0.65 * strength.freshness))
        }
        let nodeIDs = Set(nodes.map(\.id))
        var edges: [GraphEdge] = []
        var seen = Set<String>()
        for object in objects {
            guard let fromHead = headOf[object.id] else { continue }
            for cite in object.cites {
                guard let toHead = headOf[cite.id], toHead != fromHead,
                      nodeIDs.contains(fromHead), nodeIDs.contains(toHead) else { continue }
                let key = "\(fromHead)->\(toHead)"
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                let isSupport = EvidenceStrength.supportRels.contains(cite.rel)
                let isContradict = EvidenceStrength.contradictRels.contains(cite.rel)
                edges.append(GraphEdge(
                    id: key, from: fromHead, to: toHead,
                    color: isSupport ? .green : isContradict ? .red : .secondary,
                    width: isSupport || isContradict ? 2.0 : 1.0))
            }
        }
        // 사건 노드(토글) — 사실층을 그래프에 얹는다. subject/object 가 노드일 때만 연결(고아 방지).
        if showEvents {
            for event in model.allEventsRecentFirst(limit: 300) {
                let anchors = [event.subject, event.object].compactMap { $0 }.filter { nodeIDs.contains($0) }
                guard !anchors.isEmpty else { continue }
                nodes.append(GraphNode(id: event.id, label: event.rel, color: .yellow,
                                       radius: 4, opacity: 0.9))
                for anchor in anchors {
                    edges.append(GraphEdge(id: "\(event.id)->\(anchor)", from: event.id, to: anchor,
                                           color: .yellow, width: 1.0))
                }
            }
        }
        return (nodes, edges)
    }

    @State private var focusMode = true
    @State private var showEvents = false

    /// 포커스 모드 — 선택 노드 + 직접 이웃(인용·피인용)만. 헤어볼·성능 완화.
    private func focused(_ data: (nodes: [GraphNode], edges: [GraphEdge]))
        -> (nodes: [GraphNode], edges: [GraphEdge]) {
        guard focusMode, let sel = model.selectedDocumentID,
              data.nodes.contains(where: { $0.id == sel }) else { return data }
        var keep: Set<String> = [sel]
        for e in data.edges where e.from == sel || e.to == sel { keep.insert(e.from); keep.insert(e.to) }
        return (data.nodes.filter { keep.contains($0.id) },
                data.edges.filter { keep.contains($0.from) && keep.contains($0.to) })
    }

    var body: some View {
        let data = focused(graphData)
        return ForceDirectedGraph(states: graphStates) {
            Series(data.nodes) { node in
                NodeMark(id: node.id)
                    .symbol(.circle)
                    .symbolSize(radius: node.radius)
                    .foregroundStyle(node.color.opacity(node.opacity))
                    .annotation(node.id + ".label", offset: .init(dx: 0, dy: -14)) {
                        Text(node.label)
                            .font(.system(size: 9))
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(.background.opacity(0.75), in: Capsule())
                    }
            }
            Series(data.edges) { edge in
                LinkMark(from: edge.from, to: edge.to)
                    .stroke(edge.color.opacity(0.55), StrokeStyle(lineWidth: edge.width))
            }
        } force: {
            .manyBody(strength: -160)
            .center()
            .link(originalLength: 90.0, stiffness: .weightedByDegree { _, _ in 0.8 })
        }
        .graphOverlay { proxy in
            Rectangle().fill(.clear).contentShape(Rectangle())
                .withGraphDragGesture(proxy, of: String.self)
                .withGraphTapGesture(proxy, of: String.self) { id in
                    model.selectedDocumentID = id.hasSuffix(".label") ? String(id.dropLast(6)) : id
                }
                .withGraphMagnifyGesture(proxy)
        }
        .overlay(alignment: Alignment.topLeading) {
            VStack(alignment: .leading, spacing: 3) {
                legendRow(.purple, "내 기록")
                legendRow(.indigo, "위키(개념)")
                legendRow(.cyan, "엔티티")
                legendRow(.orange, "수집 근거")
                legendRow(.blue, "발행 근거")
                legendRow(.brown, "해석(판단)")
                legendRow(.red, "반박 있음")
                if showEvents { legendRow(.yellow, "사건(사실)") }
                Text("크기=지지도 · 진하기=신선도").font(.caption2).foregroundStyle(.tertiary)
                Divider().frame(width: 90)
                Toggle(isOn: $focusMode) { Text("포커스(이웃만)").font(.caption2) }
                    .toggleStyle(.checkbox).controlSize(.mini)
                Toggle(isOn: $showEvents) { Text("사건 표시").font(.caption2) }
                    .toggleStyle(.checkbox).controlSize(.mini)
                if focusMode && model.selectedDocumentID != nil {
                    Text("전체 보려면 포커스 끄기").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .padding(8)
            .background(.background.opacity(0.8), in: RoundedRectangle(cornerRadius: 8))
            .padding(10)
        }
    }

    private func legendRow(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).font(.caption2)
        }
    }
}
