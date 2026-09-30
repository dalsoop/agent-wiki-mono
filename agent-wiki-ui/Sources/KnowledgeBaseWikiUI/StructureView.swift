import KnowledgeBaseWikiCore
import SwiftUI

/// 구조 — 저장 3층(봉인·해석·파생)과 층 사이 배선 완성도.
///
/// 수치는 전부 `LedgerStructure` 가 실측한다(CLI `agent-wiki structure` 와 같은 계산).
/// 여기서는 판정을 **형태로도** 읽히게 한다 — 미달은 숫자만이 아니라 색·기호로 먼저 보인다.
struct StructureView: View {
    let root: URL
    /// 백로그 항목을 눌렀을 때 그 객체로 이동. 화면이 숫자만 보여주면 손댈 수가 없다.
    var onOpenObject: ((String) -> Void)?

    @State private var structure: LedgerStructure?
    @State private var measuring = false
    @State private var focused: LedgerStructure.Edge?
    @State private var visibleBacklog = 25

    var body: some View {
        ScrollView {
            if let structure {
                LazyVStack(alignment: .leading, spacing: 22) {
                    header(structure)
                    diagram(structure)
                    breaches(structure)
                    backlog(structure)
                    layers(structure)
                    edges(structure)
                    footnote
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ContentUnavailableView(
                    measuring ? L(.StructureViewMeasuring) : L(.StructureViewEmptyTitle),
                    systemImage: "square.stack.3d.down.right",
                    description: Text(L(.StructureViewEmptyDescription)))
                    .padding(.top, 60)
            }
        }
        .task(id: root) { await measure() }
        .toolbar {
            Button {
                Task { await measure() }
            } label: {
                Label("다시 재기", systemImage: "arrow.clockwise")
            }
            .disabled(measuring)
        }
    }

    private func measure() async {
        measuring = true
        defer { measuring = false }
        let url = root
        // 본문 스캔·blob 스니핑이 있어 메인 스레드에서 돌리면 창이 멈춘다.
        structure = await Task.detached(priority: .userInitiated) {
            LedgerStructure(root: url)
        }.value
    }

    // MARK: - 조각

    /// 배선도 — 이 화면의 본체. 표는 그림 아래 보조로 남는다.
    private func diagram(_ s: LedgerStructure) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("배선도")
            ScrollView(.horizontal, showsIndicators: true) {
                StructureDiagram(structure: s) { edge in focused = edge }
            }
            .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 6))
            if let focused {
                HStack(alignment: .top, spacing: 8) {
                    contractTag(focused.contract)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(focused.from) → \(focused.to) · \(focused.label)  \(countLabel(focused))")
                            .font(.callout.weight(.medium))
                        Text(focused.note).font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button("닫기") { self.focused = nil }.buttonStyle(.link)
                }
                .padding(10)
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
            } else {
                Text("실선 = 기준선이 걸린 간선 · 점선 = 관측만 · 굵은 선 = 불변. "
                    + "간선을 누르면 근거가 열린다.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
    }

    private func header(_ s: LedgerStructure) -> some View {
        let done = s.completion
        let all = done.satisfied == done.required
        return VStack(alignment: .leading, spacing: 6) {
            Text("배선 \(done.satisfied)/\(done.required) 충족")
                .font(.system(size: 26, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(all ? Color.primary : Color.orange)
            Text("층은 다 있어도 층을 잇는 배선이 빠지면 아무 명령도 실패하지 않는다 — "
                + "원문은 봉인됐는데 아무도 못 찾고, gc 가 산 원본을 회수 대상으로 본다.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func breaches(_ s: LedgerStructure) -> some View {
        let items = s.breaches
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("미달 \(items.count)건")
                ForEach(items, id: \.id) { edge in
                    HStack(alignment: .top, spacing: 10) {
                        Rectangle()
                            .fill(edge.contract == .invariant ? Color.red : Color.orange)
                            .frame(width: 3)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(edge.label).font(.headline)
                                contractTag(edge.contract)
                                Spacer()
                                Text(countLabel(edge))
                                    .font(.system(.callout, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            Text(edge.note)
                                .font(.callout).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(10)
                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }

    /// 미분류 백로그 — 목록이고, 누르면 그 객체로 간다.
    @ViewBuilder
    private func backlog(_ s: LedgerStructure) -> some View {
        if !s.pending.isEmpty {
            let gatedCount = s.pending.filter(\.gated).count
            VStack(alignment: .leading, spacing: 6) {
                sectionTitle("미분류 백로그")
                let isolated = s.pending.filter { $0.lack == .citation }.count
                Text(gatedCount > 0
                    ? "기준선 이후 \(gatedCount)건은 게이트 위반이다 — 먼저 처리한다."
                    : "전부 기준선 이전 부채다. 갚으면 검색 정밀도가 오르지만 도달률과는 무관하다.")
                    .font(.callout).foregroundStyle(.secondary)
                if isolated > 0 {
                    Text("그중 \(isolated)건은 인용이 없어 걸어서 닿을 수 없다 — 분류와 별개 부채다.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                // 200행을 한 번에 쏟으면 화면도 AX 트리도 무거워지고(실측: AX 조회
                // 6.9초 타임아웃) 처리에도 도움이 안 된다. 눈앞의 한 묶음만 보여주고
                // 나머지는 세어만 준다 — 총계는 위 간선이 정확히 센다.
                ForEach(s.pending.prefix(visibleBacklog), id: \.id) { item in
                    Button {
                        onOpenObject?(item.id)
                    } label: {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(item.gated ? Color.red : Color.orange.opacity(0.7))
                                .frame(width: 6, height: 6)
                            Text(item.lack == .citation ? "고립" : "미분류")
                                .font(.system(size: 9, weight: .semibold))
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(.quaternary, in: Capsule())
                                .foregroundStyle(.secondary)
                            Text(item.title).font(.callout).lineLimit(1).frame(minWidth: 0)
                            Spacer(minLength: 12)
                            Text(item.author).font(.caption).foregroundStyle(.tertiary)
                            Text(item.published, format: .dateTime.month(.twoDigits).day(.twoDigits))
                                .font(.caption).monospacedDigit().foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(onOpenObject == nil)
                    .accessibilityLabel(
                        "\(item.gated ? "게이트 위반" : "부채") "
                            + "\(item.lack == .citation ? "인용 고립" : "미분류") "
                            + "\(item.title) \(item.author)")
                    Divider()
                }
                if s.pending.count > visibleBacklog {
                    Button("\(s.pending.count - visibleBacklog)건 더 보기") {
                        visibleBacklog += 25
                    }
                    .buttonStyle(.link).font(.callout)
                }
            }
        }
    }

    private func layers(_ s: LedgerStructure) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("층")
            ForEach(s.layers, id: \.id) { layer in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(layer.name).font(.system(.body, design: .monospaced)).bold()
                        Spacer()
                        Text("\(layer.files)개 · \(humanBytes(layer.bytes))")
                            .font(.callout).monospacedDigit().foregroundStyle(.secondary)
                    }
                    Text(layer.role).font(.callout).foregroundStyle(.secondary)
                    ForEach(layer.notes, id: \.self) { note in
                        Text("· \(note)").font(.caption).foregroundStyle(.tertiary)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private func edges(_ s: LedgerStructure) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("간선")
            ForEach(s.edges, id: \.id) { edge in
                HStack(spacing: 8) {
                    Image(systemName: statusSymbol(edge.status))
                        .foregroundStyle(statusColor(edge))
                        .font(.system(size: 11))
                    Text(edge.from).font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Image(systemName: "arrow.right").font(.system(size: 8)).foregroundStyle(.tertiary)
                    Text(edge.to).font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(edge.label).font(.callout)
                    contractTag(edge.contract)
                    Spacer()
                    Text(countLabel(edge))
                        .font(.system(.callout, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(edge.status == .satisfied ? .secondary : statusColor(edge))
                }
                .help(edge.note)
                .padding(.vertical, 3)
                Divider()
            }
        }
    }

    private var footnote: some View {
        Text("수치는 디스크·인덱스·객체 본문 실측이다. 기준선(불변/목표)만 "
            + "`LedgerStructure` 에 한 번 선언돼 있고, 나머지는 원장이 답한다. "
            + "같은 계산을 `agent-wiki structure --json` 으로도 볼 수 있다.")
            .font(.caption).foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - 표현

    private func sectionTitle(_ text: String) -> some View {
        Text(text).font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary).textCase(.uppercase).kerning(0.6)
    }

    private func contractTag(_ contract: LedgerStructure.Contract) -> some View {
        let (label, color): (String, Color) = switch contract {
        case .invariant: ("불변", .red)
        case .goal: ("목표", .orange)
        case .informational: ("관측", .secondary)
        }
        return Text(label)
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(color.opacity(0.16), in: Capsule())
            .foregroundStyle(color)
    }

    private func countLabel(_ edge: LedgerStructure.Edge) -> String {
        edge.total == 1 ? (edge.actual == 1 ? "OK" : "미달") : "\(edge.actual)/\(edge.total)"
    }

    private func statusSymbol(_ status: LedgerStructure.Status) -> String {
        switch status {
        case .satisfied: "circle.fill"
        case .partial: "circle.lefthalf.filled"
        case .missing: "circle"
        }
    }

    private func statusColor(_ edge: LedgerStructure.Edge) -> Color {
        switch edge.status {
        case .satisfied: .green
        case .partial: edge.contract == .invariant ? .red : .orange
        case .missing: edge.contract == .informational ? .secondary : .red
        }
    }

    private func humanBytes(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1f MB", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.0f KB", Double(n) / 1_000) }
        return "\(n) B"
    }
}
