import Grape
import KnowledgeBaseWikiCore
import SwiftUI

/// 워크보드 — "에이전트들이 일하는 장면" 한 화면.
/// 파이프라인 단계마다 담당 에이전트가 붙어 있고(초록 점=최근 활동), 아래로 발행 스트림이 흐른다.
struct AgentWorkboard: View {
    @Bindable var model: LedgerModel

    /// 단계 → 담당 에이전트 (역할 이름 기반 정적 배치 + 무소속은 기타로).
    private static let stageAgents: [(stage: String, icon: String, agents: [String])] = [
        ("수집", "tray.and.arrow.down", ["researcher", "scraper", "capture"]),
        ("선별·분류", "checklist", ["import-classifier", "curator", "taxonomy-drafter"]),
        ("검증", "checkmark.seal", ["verifier", "consistency-checker", "validity-auditor"]),
        ("위키 종합", "books.vertical", ["wiki-maintainer", "lore-keeper"]),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 실행 중 러너 — 제일 크게
                if let status = model.runnerStatus {
                    HStack(spacing: 10) {
                        ProgressView()
                        VStack(alignment: .leading, spacing: 2) {
                            Text(status.label).font(.headline)
                            Text(status.detail).font(.callout).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                } else {
                    HStack(spacing: 8) {
                        Circle().fill(.green).frame(width: 8, height: 8)
                        Text("지금 실행 중인 에이전트 없음 — 다음 루프는 설정 › 스케줄러 참조")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }

                // 작업 위임 — task/handoff/done 그래프(위임·완료 한눈에). 원장 객체에서 파생.
                let taskGraph = LedgerTaskGraph(objects: model.objects)
                if !taskGraph.tasks.isEmpty {
                    Text("작업 위임 — 열림 \(taskGraph.open.count) / 전체 \(taskGraph.tasks.count)")
                        .font(.headline)
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(taskGraph.tasks, id: \.id) { task in
                            HStack(spacing: 8) {
                                Image(systemName: taskGraph.isDone(task.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(taskGraph.isDone(task.id) ? .green : .orange)
                                Text(task.title ?? String(task.id.prefix(8))).font(.callout).lineLimit(1).frame(minWidth: 0)
                                if let to = taskGraph.assignee[task.id] {
                                    Text("→ \(to)").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 6)
                                Text(task.author).font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .padding(10)
                    .background(.quaternary.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                }

                // 연합 구조 — 실측(인용 흐름) 도표
                Text("연합 구조 — 누가 누구의 발행을 이어받나 (인용 실측)").font(.headline)
                GeometryReader { proxy in
                    if proxy.size.width < 480 {
                        // 좁은 폭 — force 그래프 대신 간선 목록 (그래프는 빈 화면처럼 보임)
                        AllianceEdgeList(model: model)
                    } else {
                        AgentAllianceGraph(model: model)
                    }
                }
                .frame(height: 340)
                .background(.quaternary.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))

                // 대기 중 — 지금은 안 돌지만 편성된 에이전트와 다음 기동 조건
                Text("대기 중").font(.headline)
                FlowLayoutRow {
                    ForEach(waitingAgents, id: \.self) { name in
                        HStack(spacing: 5) {
                            Circle().fill(Color.secondary.opacity(0.35)).frame(width: 7, height: 7)
                            Text(name).font(.caption)
                            Text(Self.schedules[name] ?? "수동")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.quaternary.opacity(0.3), in: Capsule())
                    }
                }

                // 파이프라인 × 에이전트 배치도
                Text("파이프라인").font(.headline)
                HStack(alignment: .top, spacing: 8) {
                    ForEach(Array(Self.stageAgents.enumerated()), id: \.offset) { index, stage in
                        if index > 0 {
                            Image(systemName: "arrow.right")
                                .foregroundStyle(.tertiary).padding(.top, 24)
                        }
                        VStack(spacing: 6) {
                            Label(stage.stage, systemImage: stage.icon)
                                .font(.callout.weight(.semibold))
                            ForEach(stage.agents.filter { name in
                                model.fullRoster.contains { $0.name == name } || model.hasPublications(name)
                            }, id: \.self) { name in
                                agentChip(name)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
                    }
                }

                // 실시간 발행 스트림
                Text("발행 스트림 (실시간)").font(.headline)
                ForEach(model.recentPublications(limit: 18)) { object in
                    Button {
                        model.jump(toObject: object.id)
                    } label: {
                        HStack(spacing: 8) {
                            Text(object.published, format: .dateTime.hour().minute().second())
                                .font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                            Text(object.author)
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(agentColor(object.author).opacity(0.15), in: Capsule())
                                .foregroundStyle(agentColor(object.author))
                            StageBadge(stage: model.stage(of: object))
                            Text(object.title ?? "(무제)").font(.callout).lineLimit(1).frame(minWidth: 0)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
    }

    /// 기동 조건(스케줄러·신호 편성) — 설정 › 스케줄러와 동일한 정본.
    static let schedules: [String: String] = [
        "wiki-maintainer": "매일 03:30 야간 사서",
        "inbox-classifier": "매시 10분 신호 tick",
        "import-classifier": "수집함 신호 시",
        "validity-auditor": "감사 요청 시",
        "verifier": "매주 월 04:30 재검증",
        "consistency-checker": "매일 03:30 사서 후처리",
        "lore-keeper": "창작 세계관 작업 시",
        "researcher": "질문 위임 시",
        "checkpoint": "매일 21:30",
        "run-reaper": "매시 45분 좌초 run 수습",
    ]

    private var waitingAgents: [String] {
        // 표식(marker)·유령(ghost)·시스템 저자는 편성이 아니다 — 대기 목록에서 제외
        model.fullRoster
            .filter { $0.mode == "scheduled" || $0.mode == "on-demand" }
            .map(\.name)
            .filter { !model.isRecentlyActive($0) }
            .sorted()
    }

    private func agentChip(_ name: String) -> some View {
        let active = model.isRecentlyActive(name)
        return HStack(spacing: 5) {
            Circle().fill(active ? Color.green : Color.secondary.opacity(0.35))
                .frame(width: 7, height: 7)
            Text(name).font(.caption)
            if let last = model.lastPublished(by: name) {
                Text(last, format: .dateTime.hour().minute())
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(.background.opacity(0.8), in: Capsule())
        .onTapGesture {
            model.area = .agents
            model.selectedAgentName = name
        }
    }

    private func agentColor(_ author: String) -> Color {
        let palette: [Color] = [.blue, .green, .orange, .purple, .teal, .pink, .indigo, .brown]
        let index = abs(author.hashValue) % palette.count
        return author == "human" ? .primary.opacity(0.7) as Color : palette[index]
    }
}

/// 한 줄 넘치면 줄바꿈되는 칩 나열.
struct FlowLayoutRow<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        // macOS 15: Layout 프로토콜 간이 구현 대신 유연 그리드로 충분
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), alignment: .leading)],
                  alignment: .leading, spacing: 6) { content }
    }
}

/// 에이전트 연합 force 그래프 — 노드 크기=발행량, 간선 두께=인용 횟수(이어받은 작업량).
struct AgentAllianceGraph: View {
    @Bindable var model: LedgerModel
    @State private var graphStates = ForceDirectedGraphState(initialIsRunning: true)

    private struct AgentNode: Identifiable {
        let id: String
        let radius: Double
        let color: Color
        let active: Bool
        let count: Int
    }

    var body: some View {
        let edges = model.agentEdges()
        let names = Set(edges.flatMap { [$0.from, $0.to] })
            .union(model.fullRoster.map(\.name)).union(["human"])
        let nodes = names.sorted().map { name in
            AgentNode(
                id: name,
                radius: 8 + min(Double(model.publicationCount(of: name)).squareRoot() * 1.6, 16),
                color: Self.nodeColor(name),
                active: model.isRecentlyActive(name),
                count: model.publicationCount(of: name))
        }
        let maxCount = max(edges.first?.count ?? 1, 1)
        return ForceDirectedGraph(states: graphStates) {
            Series(nodes) { node in
                NodeMark(id: node.id)
                    .symbol(.circle)
                    .symbolSize(radius: node.radius)
                    .foregroundStyle(node.color.opacity(node.active ? 1.0 : 0.45))
                    .annotation(node.id + ".label", offset: .init(dx: 0, dy: -16)) {
                        HStack(spacing: 3) {
                            if node.active {
                                Circle().fill(.green).frame(width: 5, height: 5)
                            }
                            Text(node.id).font(.system(size: 10, weight: .medium))
                            Text("\(node.count)")
                                .font(.system(size: 9)).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(.background.opacity(0.85), in: Capsule())
                    }
            }
            Series(edges) { edge in
                LinkMark(from: edge.from, to: edge.to)
                    .stroke(.blue.opacity(0.25 + 0.6 * Double(edge.count) / Double(maxCount)),
                            StrokeStyle(lineWidth: 1 + 3 * Double(edge.count) / Double(maxCount)))
            }
        } force: {
            .manyBody(strength: -60)
            .center(strength: 0.6)
            .collide(radius: .constant(26))
            .link(originalLength: 60.0, stiffness: .weightedByDegree { _, _ in 0.6 })
        }
        .graphOverlay { proxy in
            Rectangle().fill(.clear).contentShape(Rectangle())
                .withGraphDragGesture(proxy, of: String.self)
                .withGraphTapGesture(proxy, of: String.self) { id in
                    let name = id.hasSuffix(".label") ? String(id.dropLast(6)) : id
                    model.area = .agents
                    model.selectedAgentName = name
                }
                .withGraphMagnifyGesture(proxy)
        }
        .overlay(alignment: .bottomLeading) {
            Text("굵은 선=인용 많음(작업 이어받음) · 크기=발행량 · 초록=최근 10분 활동")
                .font(.caption2).foregroundStyle(.tertiary)
                .padding(6)
        }
    }

    private static func nodeColor(_ author: String) -> Color {
        if author == "human" { return .purple }
        let palette: [Color] = [.blue, .green, .orange, .teal, .pink, .indigo, .brown, .mint]
        return palette[abs(author.hashValue) % palette.count]
    }
}

/// 좁은 폭 대체 — 인용 흐름 상위 간선을 목록으로.
struct AllianceEdgeList: View {
    @Bindable var model: LedgerModel

    var body: some View {
        let edges = model.agentEdges().prefix(8)
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(edges)) { edge in
                HStack(spacing: 6) {
                    Text(edge.from).font(.callout.weight(.medium))
                    Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.tertiary)
                    Text(edge.to).font(.callout)
                    Spacer()
                    Text("인용 \(edge.count)").font(.caption).foregroundStyle(.secondary)
                }
            }
            if edges.isEmpty {
                Text("아직 에이전트 간 인용 없음").font(.caption).foregroundStyle(.tertiary)
            }
            Spacer()
            Text("창을 넓히면 관계 그래프로 표시됩니다").font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(12)
    }
}
