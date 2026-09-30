import KnowledgeBaseWikiCore
import SwiftUI

/// 선택 객체의 사건 타임라인 — 그 객체를 subject/object 로 삼은 사건들(occurred 순).
/// 객체 중심 화면에서 "이 대상에 무슨 일이 있었나"(사건 중심)를 잇는 다리.
/// 파생 그래프(graph.db)에서 읽으며, 없으면 조용히 비운다(정본은 md·events).
struct EventTimelineSection: View {
    @Bindable var model: LedgerModel
    let objectID: String

    private var rows: [LedgerGraph.TimelineRow] { model.timeline(for: objectID) }

    var body: some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Label("사건 타임라인", systemImage: "clock.arrow.circlepath")
                    .font(.subheadline).fontWeight(.semibold)
                ForEach(rows, id: \.eventID) { row in
                    HStack(alignment: .top, spacing: 8) {
                        Circle().fill(.secondary).frame(width: 5, height: 5).padding(.top, 5)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(row.rel).font(.callout)
                            Text(shortDate(row.occurred)).font(.caption2).foregroundStyle(.tertiary)
                        }
                        Spacer()
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    /// ISO occurred 문자열을 "MM-dd HH:mm" 로 — 실패하면 원문 앞 16자.
    private func shortDate(_ iso: String) -> String {
        let parser = ISO8601DateFormatter()
        guard let date = parser.date(from: iso) else { return String(iso.prefix(16)) }
        let out = DateFormatter()
        out.dateFormat = "yyyy-MM-dd HH:mm"
        return out.string(from: date)
    }
}
