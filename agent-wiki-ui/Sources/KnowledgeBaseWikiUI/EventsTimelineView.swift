import AppKit
import KnowledgeBaseWikiCore
import SwiftUI

/// 사건층 화면 — 운영 로그를 뎁스 트리로. 작업(run)이 최상위 한 줄(성공/실패/진행),
/// 펼치면 그 작업의 단계(step: 근거검색·fetch·관측)가 드러난다. 기본은 접힘 = 요약만.
/// 사람은 T1(성공/실패)만 보고, 필요할 때 파고든다. 판단·해석은 여기 아니라 md 객체로.
struct EventsTimelineView: View {
    @Bindable var model: LedgerModel
    @State private var blobSheet: BlobPreview?
    @State private var onlyFailed = false

    struct BlobPreview: Identifiable { let id: String }   // id = blob sha

    /// 한 작업 = 시작 사건 + (완료 사건) + 단계들.
    private struct RunGroup: Identifiable {
        let start: Event
        let end: Event?
        let steps: [Event]
        var id: String { start.id }
        var outcome: Event.Outcome { end?.outcome ?? .pending }
    }

    private var runs: [RunGroup] {
        let all = model.allEventsRecentFirst(limit: 1000)
        let ends = Dictionary(grouping: all.filter { $0.level == .run && $0.outcome != .pending && $0.parent != nil },
                              by: { $0.parent! })
        let stepsByParent = Dictionary(grouping: all.filter { $0.level == .step }, by: { $0.parent ?? "" })
        return all.filter { $0.level == .run && $0.outcome == .pending }.compactMap { start in
            let g = RunGroup(start: start, end: ends[start.id]?.first,
                             steps: (stepsByParent[start.id] ?? []).sorted { $0.occurred < $1.occurred })
            if onlyFailed && g.outcome != .fail { return nil }
            return g
        }
    }

    /// 작업에 안 매인 낱개 사건(체크포인트 등 step 고아). 트리 아래 별도로.
    private var loose: [Event] {
        let all = model.allEventsRecentFirst(limit: 1000)
        let runIDs = Set(all.filter { $0.level == .run }.map(\.id))
        return all.filter { event in
            let isLoose = event.level != .run
            let parentIsNotRun = event.parent == nil || !runIDs.contains(event.parent!)
            return isLoose && parentIsNotRun
        }
    }

    var body: some View {
        Group {
            if runs.isEmpty && loose.isEmpty {
                ContentUnavailableView {
                    Label(L(.EventsTimelineViewEmptyTitle), systemImage: "clock.badge.questionmark")
                } description: {
                    Text(L(.EventsTimelineViewEmptyDescription))
                        .multilineTextAlignment(.leading)
                }
            } else {
                List {
                    if !runs.isEmpty {
                        Section("작업") {
                            ForEach(runs) { run in RunRow(run: run, jump: jump, openBlob: openBlob) }
                        }
                    }
                    if !loose.isEmpty {
                        Section("낱개 사건") {
                            ForEach(loose, id: \.id) { e in
                                StepRow(event: e, indent: false, jump: jump, openBlob: openBlob)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("사건")
        .toolbar {
            Toggle(isOn: $onlyFailed) { Label("실패만", systemImage: "xmark.octagon") }
        }
        .sheet(item: $blobSheet) { preview in blobSheetView(preview) }
    }

    private func jump(_ id: String) { model.jump(toObject: id) }
    private func openBlob(_ sha: String) { blobSheet = BlobPreview(id: sha) }

    @ViewBuilder private func blobSheetView(_ preview: BlobPreview) -> some View {
        let sha = preview.id
        let kind = model.blobKind(sha)
        let size = model.blobSize(sha)
        let refs = model.eventsForBlob(sha)
        VStack(alignment: .leading, spacing: 10) {
            // 헤더 — 종류·크기·불변성·열기
            HStack(spacing: 8) {
                Label("원본", systemImage: "shippingbox").font(.headline)
                if let kind { Text(kind.label).font(.caption).padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.blue.opacity(0.15), in: Capsule()).foregroundStyle(.blue) }
                if let size { Text(byteString(size)).font(.caption).foregroundStyle(.secondary) }
                Text("불변").font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                if kind != nil {
                    Button { model.openBlobExternally(sha) } label: { Label("기본 앱으로 열기", systemImage: "arrow.up.forward.app") }
                }
            }
            Text(sha).font(.caption2.monospaced()).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(1).frame(minWidth: 0)
            Divider()
            // 내용 — 이미지는 인라인, 텍스트는 본문, 그 외는 안내
            blobContent(sha: sha, kind: kind).frame(maxHeight: 220)
            Divider()
            // 연결된 것 — 역참조
            Text("연결된 사건 \(refs.count)").font(.subheadline).fontWeight(.semibold)
            if refs.isEmpty {
                Text("이 원본을 참조하는 사건이 없습니다.").font(.caption).foregroundStyle(.tertiary)
            } else {
                ScrollView {
                    ForEach(refs, id: \.id) { e in
                        HStack(spacing: 6) {
                            Text(e.rel).font(.callout)
                            Button(action: { model.jump(toObject: e.subject); blobSheet = nil }) {
                                Text(short(e.subject))
                            }.buttonStyle(.link)
                            Spacer()
                            Text(e.writer).font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }.frame(maxHeight: 100)
            }
            HStack { Spacer(); Button("닫기") { blobSheet = nil }.keyboardShortcut(.defaultAction) }
        }
        .padding(16).frame(width: 580, height: 520)
    }

    @ViewBuilder private func blobContent(sha: String, kind: BlobStore.Kind?) -> some View {
        if let kind, kind.previewable, let data = model.blobData(sha), let img = NSImage(data: data) {
            ScrollView { Image(nsImage: img).resizable().scaledToFit().frame(maxWidth: .infinity) }
        } else if let kind, kind.isText, let text = model.blobText(sha) {
            ScrollView { Text(text).font(.callout.monospaced()).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading) }
        } else if kind != nil {
            ContentUnavailableView(L(.EventsTimelineViewEmptyPreviewTitle, kind!.label), systemImage: "doc",
                description: Text(L(.EventsTimelineViewEmptyPreviewDesc)))
        } else {
            ContentUnavailableView(L(.EventsTimelineViewEmptyBlobTitle), systemImage: "icloud.slash",
                description: Text(L(.EventsTimelineViewEmptyBlobDesc)))
        }
    }

    private func byteString(_ n: Int) -> String {
        let kibibyte = 1024
        let mebibyte = kibibyte * 1024
        if n < kibibyte { return "\(n) B" }
        if n < mebibyte { return String(format: "%.1f KB", Double(n) / Double(kibibyte)) }
        return String(format: "%.1f MB", Double(n) / Double(mebibyte))
    }
    private func short(_ id: String) -> String { id.count > 12 && id.contains("-") ? String(id.prefix(8)) : id }

    // MARK: 행

    private struct RunRow: View {
        let run: RunGroup
        let jump: (String) -> Void
        let openBlob: (String) -> Void

        var body: some View {
            DisclosureGroup {
                if run.steps.isEmpty {
                    Text("단계 기록 없음").font(.caption2).foregroundStyle(.tertiary)
                } else {
                    ForEach(run.steps, id: \.id) { StepRow(event: $0, indent: true, jump: jump, openBlob: openBlob) }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: mark).foregroundStyle(color)
                    Text(run.start.rel).fontWeight(.medium)
                    Text(run.start.subject).foregroundStyle(.secondary).lineLimit(1).frame(minWidth: 0)
                    Spacer()
                    if !run.steps.isEmpty {
                        Text("단계 \(run.steps.count)").font(.caption2).foregroundStyle(.tertiary)
                    }
                    Text(shortTime(run.start.occurred)).font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                }
            }
        }
        private var mark: String {
            switch run.outcome { case .ok: "checkmark.circle.fill"; case .fail: "xmark.octagon.fill"; case .pending: "clock" }
        }
        private var color: Color {
            switch run.outcome { case .ok: .green; case .fail: .red; case .pending: .orange }
        }
    }

    private struct StepRow: View {
        let event: Event
        let indent: Bool
        let jump: (String) -> Void
        let openBlob: (String) -> Void

        var body: some View {
            HStack(spacing: 8) {
                if indent { Text("├").foregroundStyle(.tertiary).font(.caption) }
                Text(event.rel).font(.callout)
                if let object = event.object {
                    Button(action: { jump(object) }) { Text(short(object)) }.buttonStyle(.link)
                } else {
                    Button(action: { jump(event.subject) }) { Text(short(event.subject)) }.buttonStyle(.link)
                }
                if let source = event.source {
                    Button(action: { openBlob(source) }) {
                        Label("원본", systemImage: "doc.badge.clock").font(.caption2)
                    }.buttonStyle(.link)
                }
                ForEach(event.attrs.sorted(by: { $0.key < $1.key }), id: \.key) { k, v in
                    Text("\(k)=\(v)").font(.caption2)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(.quaternary.opacity(0.5), in: Capsule())
                }
                Spacer()
                Text(shortTime(event.occurred)).font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
            }
        }
        private func short(_ id: String) -> String { id.count > 12 && id.contains("-") ? String(id.prefix(8)) : id }
    }
}

private func shortTime(_ date: Date) -> String {
    let f = DateFormatter(); f.dateFormat = "MM-dd HH:mm"; return f.string(from: date)
}
