import KnowledgeBaseWikiCore
import SwiftUI

struct LedgerContentColumn: View {
    @Bindable var model: LedgerModel
    @Binding var showCreateRole: Bool

    var body: some View {
        switch model.area {
                // 구조는 단일 화면 — 목록 열이 없다(설정과 같은 형태).
                case .structure: EmptyView()
                case .myNotes: documentList
                case .evidence: EvidenceListView(model: model)
                case .activity: ActivityListView(model: model)
                case .graph:
                    // 2열 레이아웃 — content 열 미사용(detail 이 그래프 전체).
                    EmptyView()
                case .events:
                    EventsTimelineView(model: model)
                case .changes:
                    RecentChangesView(model: model)
                case .discuss:
                    DiscussionsView(model: model)
                case .learning:
                    LearningView(model: model)
                case .agents:
                    agentsList
                case .wiki:
                    wikiList
                case .settings:
                    // 2열 레이아웃 — Settings 장면(⌘,)이 정본. content 미사용.
                    EmptyView()
                case .trash:
                    trashList
                case .triage, .review:
                    // 2열 레이아웃 — detail 이 수집함/심사대 전체. content 미사용.
                    EmptyView()
                }
    }

    var agentsList: some View {
        List(selection: Binding(
            get: { model.selectedAgentName },
            set: { model.selectedAgentName = $0 }
        )) {
            Section {
                Button {
                    showCreateRole = true
                } label: {
                    Label("새 저장소 역할", systemImage: "person.badge.plus")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("repository-agent-role-new")
            } header: {
                Text("저장소 책임 편성")
            } footer: {
                Text(".agents/roles · 역할별 엔진은 Claude, Codex, Grok, OpenCode 중 선택")
            }
            ForEach(agentRosterSections, id: \.title) { section in
                agentRosterSection(section)
            }
        }
        .navigationSplitViewColumnWidth(min: 250, ideal: 300)
    }

    private struct AgentRosterSection {
        let title: String
        let icon: String
        let members: [LedgerModel.AgentRole]
    }

    private var agentRosterSections: [AgentRosterSection] {
        let roster = model.fullRoster
        return [
            AgentRosterSection(title: "상시 편성 — 스케줄·신호로 자동 기동", icon: "clock.arrow.2.circlepath",
                               members: roster.filter { $0.mode == "scheduled" }),
            AgentRosterSection(title: "요청 시 — 작업 위임으로 기동", icon: "hand.point.right",
                               members: roster.filter { $0.mode == "on-demand" }),
            AgentRosterSection(title: "정의 없음 — 저장소 역할로 연결 필요", icon: "exclamationmark.triangle",
                               members: roster.filter { $0.mode == "ghost" }),
            AgentRosterSection(title: "기록용 표식 — 신규 작업에 쓰지 않음", icon: "archivebox",
                               members: roster.filter { $0.mode == "marker" }),
        ]
    }

    @ViewBuilder
    private func agentRosterSection(_ section: AgentRosterSection) -> some View {
        if !section.members.isEmpty {
            Section {
                ForEach(section.members) { role in
                    agentRosterRow(role)
                        .opacity(role.mode == "marker" ? 0.55 : 1)
                        .tag(role.name)
                }
            } header: {
                Label(section.title, systemImage: section.icon).font(.caption)
            }
        }
    }

    var wikiList: some View {
        List(selection: Binding(
            get: { model.selectedDocumentID },
            set: { id in model.selectedDocumentID = id }
        )) {
            let docs = model.wikiDocuments
            ForEach(docs.filter { $0.head.effectiveType == "index" }) { doc in wikiRow(doc).tag(doc.id) }
            wikiSection("플레이북", model.playbookDocuments)
            wikiSection("개념", docs.filter { $0.head.effectiveType == "concept" })
            wikiSection("엔티티", docs.filter { $0.head.effectiveType == "entity" })
        }
        .searchable(text: $model.searchText, prompt: "위키 검색")
        .navigationSplitViewColumnWidth(min: 240, ideal: 300)
        .overlay { wikiEmptyOverlay }
    }

    @ViewBuilder
    private func wikiSection(_ title: String, _ docs: [LedgerDocument]) -> some View {
        if !docs.isEmpty {
            Section("\(title) (\(docs.count))") {
                ForEach(docs) { doc in wikiRow(doc).tag(doc.id) }
            }
        }
    }

    @ViewBuilder
    private var wikiEmptyOverlay: some View {
        if model.wikiDocuments.isEmpty && model.playbookDocuments.isEmpty {
            ContentUnavailableView(L(.LedgerContentColumnEmptyWikiTitle), systemImage: "books.vertical",
                description: Text(L(.LedgerContentColumnEmptyWikiDesc)))
        }
    }

    var trashList: some View {
        List(selection: Binding(
            get: { model.selectedDocumentID },
            set: { id in model.selectedDocumentID = id }
        )) {
            ForEach(model.retractedDocuments, id: \.document.id) { row in
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.document.title.replacingOccurrences(of: "근거: ", with: ""))
                        .strikethrough().foregroundStyle(.secondary).lineLimit(1).frame(minWidth: 0)
                    Text("폐기: \(row.retraction.body.split(separator: "\n").first.map(String.init) ?? "") — \(row.retraction.author)")
                        .font(.caption).foregroundStyle(.red).lineLimit(2).frame(minWidth: 0)
                    Text(row.retraction.published, format: .dateTime.month(.twoDigits).day(.twoDigits).hour().minute())
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                .tag(row.document.id)
            }
        }
        .navigationSplitViewColumnWidth(min: 260, ideal: 310)
        .overlay { trashEmptyOverlay }
    }

    @ViewBuilder
    private var trashEmptyOverlay: some View {
        if model.retractedDocuments.isEmpty {
            ContentUnavailableView(L(.LedgerContentColumnEmptyTrashTitle), systemImage: "trash",
                description: Text(L(.LedgerContentColumnEmptyTrashDesc)))
        }
    }

    @ViewBuilder
    func agentRosterRow(_ role: LedgerModel.AgentRole) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: "cpu").foregroundStyle(.secondary)
                Text(role.name).fontWeight(.medium)
                if role.mode != "marker" && role.mode != "ghost" {
                    HStack(spacing: 3) {
                        Image(systemName: "gearshape.2")
                        Text("엔진 \(engineDisplayName(role.engine))")
                    }
                    .font(.caption2)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(engineColor(role.engine).opacity(0.13), in: Capsule())
                    .foregroundStyle(engineColor(role.engine))
                    .help("이 역할을 실행하는 CLI — 역할 정의 파일의 engine: 한 줄로 변경 (claude/codex/grok/opencode)")
                }
            }
            Text(role.descriptionText).font(.caption).foregroundStyle(.secondary).lineLimit(2).frame(minWidth: 0)
            if let last = role.lastActiveAt {
                Text("마지막 발행 \(last, format: .dateTime.month(.twoDigits).day(.twoDigits).hour().minute())")
                    .font(.caption2).foregroundStyle(.tertiary)
            } else {
                Text("아직 발행 없음").font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }


    func wikiRow(_ doc: LedgerDocument) -> some View {
        let isPlaybook = doc.head.effectiveType == "playbook"
        return VStack(alignment: .leading, spacing: 2) {
            Text(doc.title
                .replacingOccurrences(of: "개념: ", with: "")
                .replacingOccurrences(of: "엔티티: ", with: "")
                .replacingOccurrences(of: "플레이북: ", with: ""))
                .fontWeight(.medium).lineLimit(1).frame(minWidth: 0)
            Text("판 \(doc.versions.count) · \(doc.updatedAt, format: .dateTime.month(.twoDigits).day(.twoDigits).hour().minute())")
                .font(.caption).foregroundStyle(.secondary)
        }
        .contextMenu {
            // 플레이북은 낡으면 폐기(철회)해 조회에서 감춘다 — 역사는 휴지통에 남는다.
            if isPlaybook {
                if model.showDeleted {
                    Button("복구") { model.restoreDeleted(doc) }
                } else {
                    Button("폐기 (낡은 플레이북 감추기)", role: .destructive) { model.delete(doc) }
                }
            }
        }
    }


    var documentList: some View {
        List(model.documents, selection: Binding(
            get: { model.selectedDocumentID },
            set: { id in model.select(model.documents.first { $0.id == id }) }
        )) { document in
            VStack(alignment: .leading, spacing: 2) {
                Text(document.title).fontWeight(.medium).lineLimit(1).frame(minWidth: 0)
                HStack(spacing: 6) {
                    Text(document.updatedAt, format: .dateTime.month(.twoDigits).day(.twoDigits).hour().minute())
                    Text(document.snippet).lineLimit(1).frame(minWidth: 0)
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            .tag(document.id)
            .contextMenu {
                if model.showDeleted {
                    Button("복구") { model.restoreDeleted(document) }
                } else {
                    Button("삭제", role: .destructive) { model.delete(document) }
                }
            }
        }
        .searchable(text: $model.searchText, prompt: "검색")
        .navigationSplitViewColumnWidth(min: 230, ideal: 280)
        .toolbar {
            ToolbarItemGroup {
                Button {
                    model.newDocument()
                } label: {
                    Label("새 기록", systemImage: "square.and.pencil")
                }
                .keyboardShortcut("n", modifiers: .command)
                Menu {
                    Toggle("삭제된 기록 보기", isOn: $model.showDeleted)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .overlay {
            if model.documents.isEmpty {
                ContentUnavailableView(
                    model.showDeleted ? L(.LedgerContentColumnEmptyNotesDeleted) : L(.LedgerContentColumnEmptyNotes),
                    systemImage: "square.and.pencil",
                    description: model.showDeleted ? nil : Text(L(.LedgerContentColumnEmptyNotesDesc)))
            }
        }
        .safeAreaInset(edge: .bottom) {
            if model.integrityProblemCount > 0 {
                Label("보관 무결성 문제 \(model.integrityProblemCount)건 — 백업 확인 필요", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.red).padding(6)
            } else if let error = model.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red).padding(6)
            }
        }
    }
}
