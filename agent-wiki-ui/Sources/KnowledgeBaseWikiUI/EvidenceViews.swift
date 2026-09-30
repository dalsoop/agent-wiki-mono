import Charts
import KnowledgeBaseWikiCore
import SwiftUI

/// 근거 목록 — 강화 게이지 + 감쇠(색 바램)가 첫 화면에서 읽힌다.
struct EvidenceListView: View {
    @Bindable var model: LedgerModel
    @State private var showAddEvidence = false
    @State private var showRetracted = false

    private var rows: [(document: LedgerDocument, strength: EvidenceStrength)] {
        model.evidenceReviewOnly
            ? model.shelfDocuments.filter { $0.strength.freshness < 0.5 }
                .sorted { $0.strength.freshness < $1.strength.freshness }
            : model.shelfDocuments
    }

    private var reviewCount: Int {
        model.shelfDocuments.filter { $0.strength.freshness < 0.5 }.count
    }

    var body: some View {
        List(selection: Binding(
            get: { model.selectedDocumentID },
            set: { id in model.select(model.documents.first { $0.id == id }) }
        )) {
            Section {
                DecayMapStrip(rows: model.shelfDocuments) { id in
                    model.select(model.documents.first { $0.id == id })
                }
                .listRowSeparator(.hidden)
            }
            Section {
                HStack {
                    Picker("보기", selection: $model.evidenceReviewOnly) {
                        Text("전체 \(model.shelfDocuments.count)").tag(false)
                        Text("확인 필요 \(reviewCount)").tag(true)
                    }
                    .pickerStyle(.segmented)
                    Toggle("폐기 \(model.retractedDocuments.count)", isOn: $showRetracted)
                        .toggleStyle(.button).controlSize(.small)
                }
                .listRowSeparator(.hidden)
                if showRetracted {
                    ForEach(model.retractedDocuments, id: \.document.id) { row in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.document.title.replacingOccurrences(of: "근거: ", with: ""))
                                .strikethrough().foregroundStyle(.secondary).lineLimit(1).frame(minWidth: 0)
                            Text("폐기: \(row.retraction.body.split(separator: "\n").first.map(String.init) ?? "") — \(row.retraction.author)")
                                .font(.caption).foregroundStyle(.red).lineLimit(2).frame(minWidth: 0)
                        }
                        .tag(row.document.id)
                    }
                } else {
                    ForEach(rows, id: \.document.id) { row in
                        EvidenceRow(document: row.document, strength: row.strength,
                                    domain: model.domainByDocument[row.document.id],
                                    kind: model.kindByDocument[row.document.id],
                                    knowledge: model.knowledgeByDocument[row.document.id])
                            .tag(row.document.id)
                    }
                }
            }
        }
        .searchable(text: $model.searchText, prompt: "근거 검색")
        .navigationSplitViewColumnWidth(min: 260, ideal: 310)
        .toolbar {
            ToolbarItemGroup {
                Menu {
                    Button("전체") { model.evidenceDomainFilter = nil }
                    Divider()
                    ForEach(model.allDomains, id: \.self) { domain in
                        Button(domain) { model.evidenceDomainFilter = domain }
                    }
                    Divider()
                    ForEach([("tech", "기술지식"), ("domain", "도메인지식"), ("preference", "규약")], id: \.0) { pair in
                        Button(pair.1) { model.evidenceKnowledgeFilter = pair.0 }
                    }
                    Button("지식성격 해제") { model.evidenceKnowledgeFilter = nil }
                    if !model.allObjectTags.isEmpty {
                        Divider()
                        ForEach(model.allObjectTags, id: \.self) { tag in
                            Button("#" + tag) { model.evidenceTagFilter = tag; model.evidenceDomainFilter = nil }
                        }
                    }
                } label: {
                    Label(model.evidenceDomainFilter ?? model.evidenceTagFilter.map { "#" + $0 } ?? "도메인",
                          systemImage: "line.3.horizontal.decrease.circle")
                }
                Picker("정렬", selection: $model.sortByStrength) {
                    Text("최신순").tag(false)
                    Text("지지도순").tag(true)
                }
                .pickerStyle(.segmented)
                Button {
                    showAddEvidence = true
                } label: {
                    Label("근거 추가", systemImage: "doc.badge.plus")
                }
            }
        }
        .sheet(isPresented: $showAddEvidence) {
            AddEvidenceSheet(model: model)
        }
        .overlay {
            if model.evidenceDocuments.isEmpty {
                ContentUnavailableView(L(.EvidenceViewsEmptyTitle), systemImage: "doc.text.magnifyingglass",
                    description: Text(L(.EvidenceViewsEmptyDescription)))
            }
        }
    }
}

/// 감쇠 지도 — 모든 근거를 시간축(x=발행시각) × 신선도(y) 점으로. 아래로 가라앉은 점 = 낡은 근거.
struct DecayMapStrip: View {
    let rows: [(document: LedgerDocument, strength: EvidenceStrength)]
    let onTap: (String) -> Void
    @State private var hovered: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Chart {
                RuleMark(y: .value("경계", 0.5))
                    .foregroundStyle(.orange.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3]))
                ForEach(rows, id: \.document.id) { row in
                    PointMark(
                        x: .value("마지막 확인", row.strength.lastReinforcedAt),
                        y: .value("신선도", row.strength.freshness))
                        .foregroundStyle(row.strength.contradictCount > 0 ? Color.red
                                         : row.strength.freshness < 0.5 ? .orange : .green)
                        .symbolSize(row.strength.score * 160 + 30)
                }
            }
            .chartYScale(domain: 0...1.05)
            .chartYAxis {
                AxisMarks(values: [0, 0.5, 1]) { _ in AxisGridLine() }
            }
            .frame(height: 64)
            Text("가로=마지막 확인 시각 · 높이=신선도 · 크기=지지도 · 주황 선 아래=확인 필요 (재현되면 점이 오른쪽·위로 이동)")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}

/// 근거 한 줄 — 제목(감쇠에 따라 바램) + 강화 게이지 + 재현/반박 수.
struct EvidenceRow: View {
    let document: LedgerDocument
    let strength: EvidenceStrength
    var domain: String? = nil
    var kind: String? = nil
    var knowledge: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(document.title.replacingOccurrences(of: "근거: ", with: ""))
                    .fontWeight(.medium).lineLimit(1).frame(minWidth: 0)
                    .opacity(0.45 + 0.55 * strength.freshness)  // 감쇠 = 바램
                if strength.contradictCount > 0 {
                    Label("\(strength.contradictCount)", systemImage: "bolt.fill")
                        .font(.caption2).foregroundStyle(.red)
                        .help("반박 \(strength.contradictCount)건")
                }
            }
            HStack(spacing: 8) {
                StrengthGauge(score: strength.score)
                Text("재현 \(strength.supportCount)")
                    .font(.caption).foregroundStyle(.secondary)
                Text(lastReinforcedText)
                    .font(.caption)
                    .foregroundStyle(strength.freshness < 0.5 ? Color.orange : Color.secondary)
                Spacer()
                if let domain {
                    Text(domain).font(.caption2)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(.teal.opacity(0.14), in: Capsule())
                        .foregroundStyle(.teal)
                }
                if let knowledge {
                    Text(knowledgeLabel(knowledge)).font(.caption2)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(knowledgeColor(knowledge).opacity(0.14), in: Capsule())
                        .foregroundStyle(knowledgeColor(knowledge))
                        .help(kind.map { "문서형: \($0)" } ?? "")
                }
                ForEach(document.head.tags, id: \.self) { tag in
                    Text("#" + tag).font(.caption2).foregroundStyle(.secondary)
                }
                Text(document.head.author == "human" ? "내가 발행" : document.head.author)
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    private func knowledgeLabel(_ value: String) -> String {
        switch value {
        case "tech": return "기술지식"
        case "domain": return "도메인지식"
        case "preference": return "규약"
        default: return value
        }
    }

    private func knowledgeColor(_ value: String) -> Color {
        switch value {
        case "tech": return .blue
        case "domain": return .purple
        case "preference": return .gray
        default: return .secondary
        }
    }

    private var lastReinforcedText: String {
        let days = Int(Date().timeIntervalSince(strength.lastReinforcedAt) / 86_400)
        return days == 0 ? "오늘 확인됨" : "마지막 재현 \(days)일 전"
    }
}

func knowledgeDisplay(_ value: String) -> String {
    switch value {
    case "tech": return "기술지식"
    case "domain": return "도메인지식"
    case "preference": return "규약"
    default: return value
    }
}

func knowledgeTint(_ value: String) -> Color {
    switch value {
    case "tech": return .blue
    case "domain": return .purple
    case "preference": return .gray
    default: return .secondary
    }
}

func classifierChip(_ text: String, color: Color) -> some View {
    Text(text).font(.caption)
        .padding(.horizontal, 6).padding(.vertical, 1)
        .background(color.opacity(0.13), in: Capsule())
        .foregroundStyle(color)
}

/// 강화 게이지 — 지지도(포화×감쇠) 0~1 을 5칸 막대로.
struct StrengthGauge: View {
    let score: Double

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Double(index) / 5 < score ? gaugeColor : Color.secondary.opacity(0.2))
                    .frame(width: 8, height: 8)
            }
        }
        .help(String(format: "지지도 %.0f%%", score * 100))
    }

    private var gaugeColor: Color {
        score > 0.7 ? .green : score > 0.4 ? .yellow : .orange
    }
}
