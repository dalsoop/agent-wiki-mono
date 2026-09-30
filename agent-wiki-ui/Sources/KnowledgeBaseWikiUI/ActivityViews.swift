import KnowledgeBaseWikiCore
import SwiftUI

func confidenceColor(_ value: Double) -> Color {
    value >= 0.8 ? .green : value >= 0.5 ? .orange : .red
}

/// 활동 — 에이전트 작업 묶음(batch) 카드와 일괄 되돌리기.
struct ActivityListView: View {
    @Bindable var model: LedgerModel

    var body: some View {
        List {
            ForEach(model.activityByDay, id: \.day) { group in
                Section(group.day) {
                    ForEach(group.batches) { batch in
                        batchRow(batch)
                    }
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 260, ideal: 310)
        .overlay {
            if model.activityBatches.isEmpty {
                ContentUnavailableView(L(.ActivityViewsEmptyTitle), systemImage: "cpu",
                    description: Text(L(.ActivityViewsEmptyDescription)))
            }
        }
    }

    @ViewBuilder
    private func batchRow(_ batch: LedgerModel.ActivityBatch) -> some View {
        TapDisclosure {
            if let run = model.runInfo(batch: batch) {
                RunChainView(model: model, run: run)
                Divider()
            }
            ForEach(batch.objects.filter { $0.effectiveType != "run" && $0.effectiveType != "decision" }) { object in
                Button {
                    model.jump(toObject: object.id)
                } label: {
                    HStack(spacing: 6) {
                        StageBadge(stage: model.stage(of: object))
                        LayerBadge(object: object)
                        Text(object.title ?? "(무제)").font(.callout).lineLimit(1).frame(minWidth: 0)
                        Image(systemName: "arrow.up.right").font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }
            if let conversation = model.conversationRecord(batch: batch.id) {
                Button {
                    model.jump(toObject: conversation.head.id)
                } label: {
                    Label("이 작업의 대화기록", systemImage: "text.bubble")
                        .font(.callout)
                }
                .buttonStyle(.link)
            }
            Button("이 작업 전체 되돌리기", role: .destructive) {
                model.rollback(batch: batch)
            }
            .font(.callout)
        } label: {
            batchLabel(batch)
        }
    }

    private func batchLabel(_ batch: LedgerModel.ActivityBatch) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Text(model.batchTitle(batch))
                    .fontWeight(.medium).lineLimit(1).frame(minWidth: 0)
                runBadge(for: batch)
            }
            HStack(spacing: 6) {
                Text(batch.publishedAt, format: .dateTime.hour().minute())
                Text("\(batch.actor) · \(batch.objects.count)건")
            }
            .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func runBadge(for batch: LedgerModel.ActivityBatch) -> some View {
        if let run = model.runInfo(batch: batch) {
            runStatusBadge(run)
        }
    }

    @ViewBuilder
    private func runStatusBadge(_ run: LedgerModel.RunInfo) -> some View {
        if run.abandoned {
            Text("중단 의심").font(.caption2)
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(.red.opacity(0.15), in: Capsule())
                .foregroundStyle(.red)
        } else if run.end == nil {
            Text("진행 중").font(.caption2)
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(.blue.opacity(0.15), in: Capsule())
                .foregroundStyle(.blue)
        } else if run.end?.title?.contains("중단") ?? false {
            Text("중단 종료").font(.caption2)
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(.gray.opacity(0.15), in: Capsule())
                .foregroundStyle(.gray)
        } else if let confidence = run.confidence {
            Text("확신도 \(confidence, format: .number.precision(.fractionLength(2)))")
                .font(.caption2)
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(confidenceColor(confidence).opacity(0.15), in: Capsule())
                .foregroundStyle(confidenceColor(confidence))
        } else {
            Text("완료").font(.caption2)
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(.green.opacity(0.15), in: Capsule())
                .foregroundStyle(.green)
        }
    }
}

/// run 사슬 타임라인 — 시작 → 중간 결정들 → 종료(회고). 처리의 서사를 그대로 보여준다.
struct RunChainView: View {
    @Bindable var model: LedgerModel
    let run: LedgerModel.RunInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            chainRow(icon: "play.circle", color: .blue, object: run.start,
                     caption: "시작 — " + (run.start.title ?? ""))
            ForEach(run.decisions) { decision in
                chainRow(icon: "signpost.right", color: .orange, object: decision,
                         caption: decision.title ?? "결정")
            }
            if let end = run.end {
                let isAbandoned = end.title?.contains("중단") ?? false
                chainRow(icon: isAbandoned ? "xmark.circle" : "checkmark.circle",
                         color: isAbandoned ? .gray : .green, object: end,
                         caption: (isAbandoned ? "중단 확인 — " : "종료 — ") + (end.title ?? ""))
                ForEach(retrospectiveLines(end), id: \.self) { line in
                    Text(line).font(.caption).foregroundStyle(.secondary)
                        .padding(.leading, 24)
                }
            } else if run.abandoned {
                Label("종료 기록 없음 — 중단됐을 수 있음 (로그·대화기록 확인)", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.red)
            } else {
                Label("진행 중 — 종료 기록 대기", systemImage: "ellipsis.circle")
                    .font(.caption).foregroundStyle(.blue)
            }
        }
        .padding(.vertical, 4)
    }

    private func chainRow(icon: String, color: Color, object: LedgerObject, caption: String) -> some View {
        Button {
            model.jump(toObject: object.id)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon).foregroundStyle(color)
                Text(caption).font(.callout).lineLimit(1).frame(minWidth: 0)
                Spacer()
                Text(object.published, format: .dateTime.hour().minute())
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
    }

    private func retrospectiveLines(_ end: LedgerObject) -> [String] {
        end.body.split(separator: "\n").map(String.init).filter {
            $0.hasPrefix("확신도:") || $0.hasPrefix("어려웠던 점:") || $0.hasPrefix("배운 점:")
    }
    }
}

/// 행 전체가 탭 대상인 아코디언 — 작은 화살표만 클릭되는 DisclosureGroup 불편 해소.
struct TapDisclosure<Label: View, Content: View>: View {
    @State private var isExpanded = false
    private let content: () -> Content
    private let label: () -> Label

    init(@ViewBuilder _ content: @escaping () -> Content, @ViewBuilder label: @escaping () -> Label) {
        self.content = content
        self.label = label
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            content()
        } label: {
            label()
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
                }
        }
    }
}
