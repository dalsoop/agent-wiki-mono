import KnowledgeBaseWikiCore
import SwiftUI

/// 기록 목록 — 모델 `model.law.records: [LawRecordListRow]`, 거르기 `model.law.recordFilter` / `model.setLawRecordFilter(_:)`, 줄을 누르면 `model.showLawRecord(id:)`.
/// 검색어가 있으면 전신 포함 범위 검색(전신 결과는 행의 `scopeMark` 그대로), 4종류·유형 거르기. 표시 모델은 엔진이 배경에서 만든다.
/// 근거: docs/business-rules.md "전신"(검색 범위·전신 표시)·"사실인정과 4종류"·"유형"(지식 기록).
struct LawRecordsView: View {
    @Bindable var model: LedgerModel
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L(.LawNavRecords)).font(.title2.weight(.semibold))
                Spacer()
                if !model.isReadOnlyWorld {
                    Button {
                        model.newLawRecord()
                    } label: {
                        Label(L(.lawRecordNew), systemImage: "square.and.pencil")
                    }
                    .disabled(model.law.isWriting)
                }
            }
            LawRecordFilterBar(model: model, query: $query)
            Divider()
            if model.law.records.isEmpty {
                LawContentsEmptyState(
                    title: L(model.law.recordFilter.query.isEmpty ? .lawRecordListEmptyTitle : .lawRecordListNoMatchTitle),
                    detail: L(model.law.recordFilter.query.isEmpty ? .lawRecordListEmptyDesc : .lawRecordListNoMatchDesc))
                Spacer()
            } else {
                List(model.law.records) { row in
                    LawRecordListRowView(model: model, row: row)
                }
                .listStyle(.inset)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { query = model.law.recordFilter.query }
        .accessibilityIdentifier("law-screen-records")
    }
}

/// 검색창과 거르기(4종류·유형·전신 포함).
private struct LawRecordFilterBar: View {
    @Bindable var model: LedgerModel
    @Binding var query: String

    var body: some View {
        HStack(spacing: 10) {
            TextField(L(.lawRecordSearchPlaceholder), text: $query)
                .textFieldStyle(.roundedBorder)
                .onSubmit { update { $0.query = query } }
                .frame(minWidth: 180)
            Picker(L(.lawRecordFilterKind), selection: kindBinding) {
                Text(L(.lawRecordFilterAll)).tag(String?.none)
                ForEach(LawMemoryKind.allCases, id: \.rawValue) { kind in
                    Text(LawRecordText.memoryKind(kind)).tag(String?.some(kind.rawValue))
                }
            }
            .fixedSize()
            Picker(L(.lawRecordFilterType), selection: typeBinding) {
                Text(L(.lawRecordFilterAll)).tag(String?.none)
                ForEach(LawRecordList.listedTypes.map(\.rawValue), id: \.self) { raw in
                    Text(raw).tag(String?.some(raw))
                }
            }
            .fixedSize()
            Toggle(L(.lawRecordFilterPredecessors), isOn: predecessorBinding)
                .help(L(.lawRecordFilterPredecessorsHelp))
        }
    }

    private func update(_ change: (inout LawRecordListFilter) -> Void) {
        var filter = model.law.recordFilter
        change(&filter)
        model.setLawRecordFilter(filter)
    }

    private var kindBinding: Binding<String?> {
        Binding(
            get: { model.law.recordFilter.memoryKind?.rawValue },
            set: { raw in update { $0.memoryKind = raw.flatMap(LawMemoryKind.init(rawValue:)) } })
    }

    private var typeBinding: Binding<String?> {
        Binding(
            get: { model.law.recordFilter.type?.rawValue },
            set: { raw in update { $0.type = LawRecordList.listedTypes.first { $0.rawValue == raw } } })
    }

    private var predecessorBinding: Binding<Bool> {
        Binding(
            get: { model.law.recordFilter.includePredecessors },
            set: { value in update { $0.includePredecessors = value } })
    }
}

/// 목록 한 줄 — 제목, 범위 표시(`[전신 <원장>]` 등), 유형, 4종류, 공포일, 작성자.
private struct LawRecordListRowView: View {
    @Bindable var model: LedgerModel
    let row: LawRecordListRow

    var body: some View {
        Button {
            model.showLawRecord(id: row.id)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if !row.scopeMark.isEmpty {
                        Text(row.scopeMark)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(row.isPredecessor ? .orange : .secondary)
                    }
                    Text(row.title ?? LawRecordText.shortID(row.id))
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if let kind = row.memoryKind {
                        Text(LawRecordText.memoryKind(kind))
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(.teal.opacity(0.15), in: Capsule())
                    }
                }
                HStack(spacing: 6) {
                    Text(LawRecordText.shortID(row.id)).font(.caption.monospaced())
                    if let type = row.type { Text(type).font(.caption) }
                    Text(LawRecordText.date(row.promulgated)).font(.caption)
                    Text(row.author).font(.caption).lineLimit(1)
                }
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
