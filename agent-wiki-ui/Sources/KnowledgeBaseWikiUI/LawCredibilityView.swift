import KnowledgeBaseWikiCore
import SwiftUI

/// 모델 신빙성 — 모델 `model.law.credibility: LawCredibilityScreen?`, 기간 `model.setCredibilityPeriod(_:)`, 줄 펼침 `LawCredibilityScreen.items(for:)`.
/// 실행 도구 × 모델 × 추론 강도별 공포 수와 개정·폐지·이의 후 뒤집힌 비율만 보인다. 자동 가중치·점수는 없다.
/// 근거: docs/business-rules.md "드리밍"(보고와 `report models`).
struct LawCredibilityView: View {
    @Bindable var model: LedgerModel
    @State private var expanded: Set<String> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(L(.LawNavCredibility)).font(.title2.weight(.semibold))
                Picker(L(.LawCredibilityPeriodLabel), selection: Binding(
                    get: { model.law.credibilityPeriod },
                    set: { model.setCredibilityPeriod($0) })
                ) {
                    ForEach(LawCredibilityPeriod.allCases, id: \.self) { period in
                        Text(periodName(period)).tag(period)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .accessibilityIdentifier("law-credibility-period")
                Text(L(.LawCredibilityNote)).font(.caption).foregroundStyle(.secondary)
                if let screen = model.law.credibility, screen.period == model.law.credibilityPeriod {
                    if screen.isEmpty {
                        ContentUnavailableView(
                            L(.LawCredibilityEmptyTitle), systemImage: "chart.bar.doc.horizontal",
                            description: Text(L(.LawCredibilityEmptyDesc)))
                    } else {
                        table(screen)
                    }
                } else {
                    ProgressView(L(.LawCredibilityLoading))
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .accessibilityIdentifier("law-screen-credibility")
    }

    private func periodName(_ period: LawCredibilityPeriod) -> String {
        switch period {
        case .all: return L(.LawCredibilityPeriodAll)
        case .last30Days: return L(.LawCredibilityPeriodRecent, LawCredibilityPeriod.recentDays)
        }
    }

    private func table(_ screen: LawCredibilityScreen) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
            GridRow {
                Text("")
                Text(L(.LawCredibilityRuntime))
                Text(L(.LawCredibilityModel))
                Text(L(.LawCredibilityEffort))
                Text(L(.LawCredibilityEnacted)).gridColumnAlignment(.trailing)
                Text(L(.LawCredibilityAmendedRate)).gridColumnAlignment(.trailing)
                Text(L(.LawCredibilityRepealedRate)).gridColumnAlignment(.trailing)
                Text(L(.LawCredibilityOverturnedRate)).gridColumnAlignment(.trailing)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            Divider()
            ForEach(screen.rows, id: \.groupID) { row in
                let isOpen = expanded.contains(row.groupID)
                GridRow {
                    Image(systemName: isOpen ? "chevron.down" : "chevron.right").foregroundStyle(.secondary)
                    Text(row.runtime)
                    Text(row.model).textSelection(.enabled)
                    Text(row.effort)
                    Text("\(row.enacted)").monospacedDigit()
                    rate(row.amendedRate, count: row.amended)
                    rate(row.repealedRate, count: row.repealed)
                    rate(row.overturnedRate, count: row.overturned)
                }
                .font(.callout)
                .contentShape(Rectangle())
                .onTapGesture { toggle(row.groupID) }
                .accessibilityIdentifier("law-credibility-row")
                if isOpen {
                    LawCredibilityItems(model: model, items: screen.items(for: row))
                        .gridCellColumns(8)
                        .padding(.leading, 24)
                }
                Divider()
            }
        }
    }

    private func rate(_ value: Double, count: Int) -> some View {
        Text("\(value.formatted(.percent.precision(.fractionLength(0...1)))) (\(count))").monospacedDigit()
    }

    private func toggle(_ id: String) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }
}

private extension LawModelReportRow {
    /// 펼침 상태의 열쇠(실행 도구·모델·추론 강도).
    var groupID: String { "\(runtime)\u{1F}\(model)\u{1F}\(effort)" }
}

/// 줄 펼침 — 그 조합이 쓴 기록 중 개정·폐지·뒤집힌 기록, 각 기록으로 이동.
struct LawCredibilityItems: View {
    @Bindable var model: LedgerModel
    let items: [LawCredibilityItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if items.isEmpty {
                Text(L(.LawCredibilityItemsEmpty)).font(.caption).foregroundStyle(.secondary)
            }
            ForEach(items) { item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Button(String(item.id.prefix(8))) { model.showLawRecord(id: item.id) }
                        .buttonStyle(.link)
                        .font(.caption.monospaced())
                    Text(item.record.record.title ?? "").font(.callout).lineLimit(1)
                    if item.amended { tag(L(.LawCredibilityTagAmended)) }
                    if item.repealed { tag(L(.LawCredibilityTagRepealed)) }
                    if item.overturned { tag(L(.LawCredibilityTagOverturned)) }
                }
            }
        }
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(.quaternary, in: Capsule())
    }
}
