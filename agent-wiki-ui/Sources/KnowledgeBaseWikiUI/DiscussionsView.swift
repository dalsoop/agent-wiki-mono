import KnowledgeBaseWikiCore
import SwiftUI

/// 토론 — 위키 전역 토론 스레드(나무위키 토론). 미답변(사서 처리 대상) 우선.
/// 제목 클릭 → 토론 대상 문서로 점프. '살아있는 위키'의 심의 루프를 눈에 보이게.
struct DiscussionsView: View {
    @Bindable var model: LedgerModel
    @State private var onlyOpen = false

    private var threads: [DiscussionThread] {
        let all = model.discussionThreads()
        return onlyOpen ? all.filter(\.isOpen) : all
    }
    private var openCount: Int { model.discussionThreads().filter(\.isOpen).count }

    var body: some View {
        Group {
            if threads.isEmpty {
                ContentUnavailableView(L(.DiscussionsViewEmptyTitle), systemImage: "bubble.left.and.bubble.right",
                    description: Text(L(.DiscussionsViewEmptyDescription)))
            } else {
                List {
                    Section {
                        ForEach(threads, id: \.topicID) { t in row(t) }
                    } header: {
                        Text("미답변 \(openCount) · 전체 \(model.discussionThreads().count)")
                    }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("토론")
        .toolbar { Toggle(isOn: $onlyOpen) { Label("미답변만", systemImage: "exclamationmark.bubble") } }
    }

    @ViewBuilder private func row(_ t: DiscussionThread) -> some View {
        HStack(alignment: .top, spacing: 8) {
            // 상태
            Image(systemName: t.isOpen ? "circle.fill" : "checkmark.circle")
                .foregroundStyle(t.isOpen ? .orange : .green).font(.caption).padding(.top, 3)
            // 종류
            Text(t.kind.label).font(.system(size: 10, weight: .semibold))
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(kindColor(t.kind).opacity(0.16), in: Capsule())
                .foregroundStyle(kindColor(t.kind))
            VStack(alignment: .leading, spacing: 1) {
                Button(action: { model.jump(toObject: t.targetID.isEmpty ? t.topicID : t.targetID) }) {
                    Text(t.title).lineLimit(1).frame(minWidth: 0)
                }.buttonStyle(.link)
                HStack(spacing: 6) {
                    Text(t.isOpen ? "미답변" : "답변 \(t.responseCount)")
                        .font(.caption2).foregroundStyle(t.isOpen ? .orange : .secondary)
                    Text("· \(t.author)").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 1)
    }

    private func kindColor(_ k: DiscussionThread.Kind) -> Color {
        switch k { case .objection: .red; case .editRequest: .purple; case .question: .blue; case .other: .gray }
    }
}
