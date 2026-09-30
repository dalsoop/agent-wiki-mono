import KnowledgeBaseWikiCore
import SwiftUI

/// 학습 — 회고 에이전트의 경험학습 전용 공간. 카르파시식 "경험에서 학습"을 시간별로 관리.
/// 위: 시간별 지표(작업 성공률·개정·철회·경험칙) — 나아지는지 추세로. 아래: 경험칙(회고) 목록.
struct LearningView: View {
    @Bindable var model: LedgerModel

    private var metrics: [PeriodMetrics] { model.learningMetrics() }
    private var rules: [LedgerObject] { model.retrospectives() }
    private var summary: (successRate: Double, rules: Int, retractions: Int) {
        LearningMetrics.summary(metrics)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                // 요약 카드
                HStack(spacing: 12) {
                    stat("작업 성공률", pct(summary.successRate), NamuTheme.brand)
                    stat("경험칙", "\(summary.rules)", .purple)
                    stat("철회", "\(summary.retractions)", .orange)
                }

                // distiller 세대 진화 — 반려 피드백으로 역할이 세대별로 나아지나
                generationPanel

                Divider()

                // 시간별 지표 — 나아지는가
                Text("시간별 지표").font(.headline)
                if metrics.isEmpty {
                    Text("아직 데이터 없음 — 사건이 쌓이면 일자별 지표가 뜹니다.")
                        .font(.caption).foregroundStyle(.tertiary)
                } else {
                    VStack(spacing: 4) {
                        ForEach(metrics, id: \.day) { m in dayRow(m) }
                    }
                }

                Divider()

                // 경험칙(회고) — 학습 산출물
                HStack {
                    Text("경험칙 (회고)").font(.headline)
                    Text("\(rules.count)").foregroundStyle(.secondary)
                }
                if rules.isEmpty {
                    ContentUnavailableView {
                        Label(L(.LearningViewEmptyTitle), systemImage: "brain")
                    } description: {
                        Text(L(.LearningViewEmptyDescription))
                            .multilineTextAlignment(.leading)
                    }
                } else {
                    ForEach(rules) { r in
                        Button(action: { model.jump(toObject: r.id) }) {
                            HStack(spacing: 8) {
                                Image(systemName: "lightbulb").foregroundStyle(.purple)
                                Text((r.title ?? "").replacingOccurrences(of: "회고: ", with: "")).lineLimit(2).frame(minWidth: 0)
                                Spacer()
                                Text(r.published, format: .dateTime.month().day()).font(.caption2).foregroundStyle(.tertiary)
                            }
                        }.buttonStyle(.plain)
                    }
                }
            }
            .padding(16)
        }
        .navigationTitle("학습")
    }

    /// distiller 세대 진화 — 세대별 수용률(수락/(수락+반려))을 시간축으로. 나아지면 막대가 올라간다.
    private var generationPanel: some View {
        let gens = model.distillerGenerationStats()
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("distiller 세대").font(.headline)
                Spacer()
                Button { model.evolveDistiller() } label: {
                    Label("세대 진화", systemImage: "arrow.triangle.branch").font(.caption)
                }
                .help("사람이 반려한 심사 피드백으로 distiller 역할을 다음 세대로 개정")
            }
            Text("반려 피드백을 역할에 반영해 세대를 올린다 — 세대가 갈수록 수용률이 오르면 배우는 중.")
                .font(.caption2).foregroundStyle(.tertiary)
            if gens.allSatisfy({ $0.total == 0 }) {
                Text("아직 정제본이 없습니다 — 수집→distill 하면 세대 통계가 쌓입니다.")
                    .font(.caption).foregroundStyle(.tertiary).padding(.vertical, 4)
            } else {
                HStack(alignment: .bottom, spacing: 10) {
                    ForEach(gens) { g in genBar(g) }
                }
                .frame(height: 96)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder private func genBar(_ g: LedgerModel.GenerationStat) -> some View {
        VStack(spacing: 3) {
            if let rate = g.acceptanceRate {
                Text(String(format: "%.0f%%", rate * 100)).font(.caption2.monospacedDigit())
            } else {
                Text("—").font(.caption2).foregroundStyle(.tertiary)
            }
            GeometryReader { geo in
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(NamuTheme.brand.opacity(0.75))
                        .frame(height: max(3, geo.size.height * (g.acceptanceRate ?? 0)))
                }
            }
            Text("G\(g.index)").font(.caption2.weight(.semibold))
            Text("✓\(g.accepted) ✗\(g.rejected)\(g.pending > 0 ? " ·\(g.pending)" : "")")
                .font(.system(size: 9)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func stat(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.title2.weight(.semibold).monospacedDigit()).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private func dayRow(_ m: PeriodMetrics) -> some View {
        HStack(spacing: 10) {
            Text(m.day).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 82, alignment: .leading)
            // 성공률 바
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary.opacity(0.4))
                    Capsule().fill(NamuTheme.brand.opacity(0.7))
                        .frame(width: m.runsTotal == 0 ? 0 : geo.size.width * m.successRate)
                }
            }.frame(height: 8)
            Text(m.runsTotal == 0 ? "—" : "\(m.runsOk)/\(m.runsTotal)")
                .font(.caption2.monospacedDigit()).frame(width: 40, alignment: .trailing)
            Label("\(m.revisions)", systemImage: "pencil").font(.caption2).foregroundStyle(.blue)
            Label("\(m.retractions)", systemImage: "trash").font(.caption2).foregroundStyle(.orange)
            if m.newRules > 0 { Label("\(m.newRules)", systemImage: "lightbulb").font(.caption2).foregroundStyle(.purple) }
        }
    }

    private func pct(_ d: Double) -> String { String(format: "%.0f%%", d * 100) }
}
