import KnowledgeBaseWikiCore
import SwiftUI

/// 최근 변경 — 지식 문서의 신규·개정·철회 피드(나무위키 RecentChanges). 위키가 살아있음을 보인다.
/// 사건(운영)과 별개로 "무엇이 바뀌었나"를 시간순으로. 제목 클릭 → 그 문서로 점프.
struct RecentChangesView: View {
    @Bindable var model: LedgerModel
    @State private var onlyRevisions = false
    @State private var diffTarget: DiffTarget?

    struct DiffTarget: Identifiable { let id: String; let title: String }

    private var changes: [KnowledgeChange] {
        let all = model.recentKnowledgeChanges()
        return onlyRevisions ? all.filter { $0.kind != .new } : all
    }

    var body: some View {
        Group {
            if changes.isEmpty {
                ContentUnavailableView(L(.RecentChangesViewEmptyTitle), systemImage: "clock.arrow.2.circlepath",
                    description: Text(L(.RecentChangesViewEmptyDescription)))
            } else {
                List {
                    ForEach(grouped, id: \.day) { section in
                        Section(section.day) {
                            ForEach(section.rows, id: \.id) { c in row(c) }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("최근 변경")
        .toolbar { Toggle(isOn: $onlyRevisions) { Label("개정만", systemImage: "pencil") } }
        .sheet(item: $diffTarget) { t in diffSheet(t) }
    }

    @ViewBuilder private func diffSheet(_ t: DiffTarget) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("개정 비교", systemImage: "plusminus").font(.headline)
                Text(t.title).foregroundStyle(.secondary).lineLimit(1).frame(minWidth: 0)
                Spacer()
                Button("닫기") { diffTarget = nil }.keyboardShortcut(.defaultAction)
            }
            Divider()
            if let diff = model.revisionDiff(t.id) {
                let s = TextDiff.stat(diff)
                Text("＋\(s.added)  －\(s.removed)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(diff.enumerated()), id: \.offset) { _, line in diffLineRow(line) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ContentUnavailableView(
                    L(.RecentChangesViewEmptyDiffTitle),
                    systemImage: "doc",
                    description: Text(L(.RecentChangesViewEmptyDiffDescription))
                )
            }
        }
        .padding(16).frame(width: 620, height: 520)
    }

    @ViewBuilder private func diffLineRow(_ line: DiffLine) -> some View {
        switch line {
        case .same(let t):
            if !t.isEmpty {
                Text("  " + t).font(.caption.monospaced()).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .added(let t):
            Text("＋ " + t).font(.caption.monospaced()).foregroundStyle(.green)
                .frame(maxWidth: .infinity, alignment: .leading).background(.green.opacity(0.08))
        case .removed(let t):
            Text("－ " + t).font(.caption.monospaced()).foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading).background(.red.opacity(0.08))
        }
    }

    @ViewBuilder private func row(_ c: KnowledgeChange) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(time(c.published)).font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                .frame(width: 42, alignment: .leading)
            badge(c)
            VStack(alignment: .leading, spacing: 1) {
                Button(action: { model.jump(toObject: c.id) }) {
                    Text(c.title).lineLimit(1).frame(minWidth: 0)
                }.buttonStyle(.link)
                HStack(spacing: 6) {
                    Label(c.author, systemImage: c.author == "human" ? "person" : "cpu")
                        .font(.caption2).foregroundStyle(.tertiary)
                    if let r = c.reason { Text("— \(r)").font(.caption2).foregroundStyle(.secondary).lineLimit(1).frame(minWidth: 0) }
                }
            }
            Spacer()
            if c.kind == .revised {
                Button { diffTarget = DiffTarget(id: c.id, title: c.title) } label: {
                    Label("비교", systemImage: "plusminus").labelStyle(.iconOnly)
                }.buttonStyle(.borderless).help("이전 판과 diff")
            }
        }
        .padding(.vertical, 1)
    }

    @ViewBuilder private func badge(_ c: KnowledgeChange) -> some View {
        switch c.kind {
        case .new:
            tag("신규", .green)
        case .revised:
            tag(c.deltaChars >= 0 ? "＋\(c.deltaChars)" : "－\(-c.deltaChars)", c.deltaChars >= 0 ? .blue : .orange)
        case .retracted:
            tag("철회", .red)
        }
    }
    private func tag(_ t: String, _ color: Color) -> some View {
        Text(t).font(.system(size: 10, weight: .semibold).monospacedDigit())
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(color.opacity(0.16), in: Capsule()).foregroundStyle(color)
            .frame(minWidth: 40)
    }

    private var grouped: [(day: String, rows: [KnowledgeChange])] {
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        var order: [String] = []; var map: [String: [KnowledgeChange]] = [:]
        for c in changes {
            let d = fmt.string(from: c.published)
            if map[d] == nil { order.append(d) }
            map[d, default: []].append(c)
        }
        return order.map { ($0, map[$0] ?? []) }
    }
    private func time(_ d: Date) -> String { let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: d) }
}
