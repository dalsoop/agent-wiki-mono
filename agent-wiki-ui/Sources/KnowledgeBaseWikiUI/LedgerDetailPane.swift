import KnowledgeBaseWikiCore
import SwiftUI

struct LedgerDetailPane: View {
    @Bindable var model: LedgerModel
    @Environment(\.openSettings) private var openSettings
    @Binding var showAgentTask: Bool
    @Binding var agentTaskRole: String
    @State private var showHistory = false
    @State private var showAttachCitation = false

    var body: some View {
        switch model.destination {
        case .overview: RepositoryOverviewView(model: model)
        case .tasks: RepositoryTasksView(model: model)
        case .promotion: PromotionQueueView(model: model)
        case .administration:
            // 관리 하위 네비의 "구조" 는 area 를 바꾸는데, 이 목적지가 항상 자기
            // 개요를 그리면 그 버튼이 **아무 일도 하지 않는다.** 실제로 그렇게
            // 배포됐고(2026-08-04), 화면을 눌러보지 않아 CLI·테스트로는 안 잡혔다.
            if model.area == .structure {
                legacyDetailColumn
            } else {
                AdministrationOverviewView(model: model)
            }
        case .knowledge, .contributors: legacyDetailColumn
        }
    }

    @ViewBuilder var legacyDetailColumn: some View {
        switch model.area {
                case .structure:
                    if let root = model.store?.root {
                        StructureView(root: root) { id in
                            // 백로그에서 바로 그 객체로 — 구조 화면이 진단에서 처치로 이어진다.
                            model.area = .evidence
                            model.jump(toObject: id)
                        }
                    } else {
                        ContentUnavailableView(L(.LedgerDetailPaneEmptyPickLedger), systemImage: "folder.badge.questionmark")
                    }
                case .myNotes: editor
                case .evidence:
                    if let document = model.selectedDocument {
                        EvidenceDetailView(model: model, document: document)
                    } else {
                        ContentUnavailableView(L(.LedgerDetailPaneEmptyPickEvidence), systemImage: "doc.text.magnifyingglass",
                            description: Text(L(.LedgerDetailPaneEmptyPickEvidenceDesc)))
                    }
                case .activity:
                    AgentWorkboard(model: model)
                case .settings:
                    // Settings 장면(⌘,)과 사이드바 중복 제거 — 짧은 진입만 남긴다.
                    ContentUnavailableView {
                        Label(L(.LedgerDetailPaneEmptySettingsTitle), systemImage: "gearshape")
                    } description: {
                        Text(L(.LedgerDetailPaneEmptySettingsDesc))
                    } actions: {
                        Button(L(.LedgerDetailPaneEmptySettingsOpen)) { openSettings() }
                            .buttonStyle(.borderedProminent)
                    }
                case .trash:
                    if let row = model.retractedDocuments.first(where: { $0.document.id == model.selectedDocumentID }) {
                        TrashDetailView(model: model, row: row)
                    } else {
                        ContentUnavailableView(L(.LedgerDetailPaneEmptyPickTrash), systemImage: "trash",
                            description: Text(L(.LedgerDetailPaneEmptyPickTrashDesc)))
                    }
                case .wiki:
                    if let document = model.selectedDocument {
                        WikiReaderView(model: model, document: document)
                    } else {
                        ContentUnavailableView(L(.LedgerDetailPaneEmptyPickWiki), systemImage: "books.vertical",
                            description: Text(L(.LedgerDetailPaneEmptyPickWikiDesc)))
                    }
                case .agents:
                    if let name = model.selectedAgentName {
                        VStack(spacing: 0) {
                        agentToolbar(name)
                        Divider()
                        AgentDefinitionView(model: model, name: name)
                        Divider()
                        List(model.publications(by: name)) { object in
                            Button {
                                model.jump(toObject: object.id)
                            } label: {
                                HStack(spacing: 6) {
                                    StageBadge(stage: model.stage(of: object))
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(object.title ?? "(무제)").lineLimit(1).frame(minWidth: 0)
                                        Text(object.published, format: .dateTime.month(.twoDigits).day(.twoDigits).hour().minute())
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.up.right").font(.caption2).foregroundStyle(.tertiary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        }
                    } else {
                        ContentUnavailableView(L(.LedgerDetailPaneEmptyPickAgent), systemImage: "cpu",
                            description: Text(L(.LedgerDetailPaneEmptyPickAgentDesc)))
                    }
                case .triage: TriageView(model: model)
                case .review: ReviewBoardView(model: model)
                case .graph:
                    if let document = model.selectedDocument {
                        HSplitView {
                            LedgerGraphView(model: model)
                                .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
                            VStack(spacing: 0) {
                                graphDocumentPane(document)
                                EventTimelineSection(model: model, objectID: document.id)
                                    .padding(.horizontal, 12).padding(.bottom, 12)
                            }
                            .frame(minWidth: 300, maxWidth: 460)
                        }
                        // HSplitView 는 스스로 안 늘어난다
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        LedgerGraphView(model: model)
                    }
                case .events:
                    if let document = model.selectedDocument {
                        WikiReaderView(model: model, document: document)
                    } else {
                        ContentUnavailableView(L(.LedgerDetailPaneEmptyEventsTitle), systemImage: "clock.arrow.circlepath",
                            description: Text(L(.LedgerDetailPaneEmptyEventsDesc)))
                    }
                case .changes:
                    if let document = model.selectedDocument {
                        WikiReaderView(model: model, document: document)
                    } else {
                        ContentUnavailableView(L(.LedgerDetailPaneEmptyChangesTitle), systemImage: "clock.arrow.2.circlepath",
                            description: Text(L(.LedgerDetailPaneEmptyChangesDesc)))
                    }
                case .discuss:
                    if let document = model.selectedDocument {
                        WikiReaderView(model: model, document: document)
                    } else {
                        ContentUnavailableView(L(.LedgerDetailPaneEmptyDiscussTitle), systemImage: "bubble.left.and.bubble.right",
                            description: Text(L(.LedgerDetailPaneEmptyDiscussDesc)))
                    }
                case .learning:
                    if let document = model.selectedDocument {
                        WikiReaderView(model: model, document: document)
                    } else {
                        ContentUnavailableView(L(.LedgerDetailPaneEmptyLearningTitle), systemImage: "brain",
                            description: Text(L(.LedgerDetailPaneEmptyLearningDesc)))
                    }
                }
    }

    @ViewBuilder
    var editor: some View {
        if let document = model.selectedDocument {
            VStack(alignment: .leading, spacing: 0) {
                TextField("제목", text: $model.editorTitle)
                    .font(.title2.weight(.semibold))
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 8)
                    .onChange(of: model.editorTitle) { model.editorChanged() }
                Divider().padding(.horizontal, 20)
                TextEditor(text: $model.editorBody)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .onChange(of: model.editorBody) { model.editorChanged() }

                editorCitations(document)
                editorReferences(document)
            }
            .toolbar {
                ToolbarItemGroup {
                    Button {
                        showAttachCitation = true
                    } label: {
                        Label("근거 붙이기", systemImage: "link.badge.plus")
                    }
                    if document.versions.count > 1 {
                        Text("판 \(document.versions.count)").font(.caption).foregroundStyle(.secondary)
                    }
                    Button {
                        showHistory = true
                    } label: {
                        Label("기록", systemImage: "clock.arrow.circlepath")
                    }
                    .disabled(document.versions.count < 2)
                }
            }
            .sheet(isPresented: $showHistory) {
                HistorySheet(model: model, document: document)
            }
            .sheet(isPresented: $showAttachCitation) {
                AttachCitationSheet(model: model, document: document)
            }
        } else {
            ContentUnavailableView(L(.LedgerDetailPaneEmptyPickNote), systemImage: "square.and.pencil",
                description: Text(L(.LedgerDetailPaneEmptyPickNoteDesc)))
        }
    }

    private func agentToolbar(_ name: String) -> some View {
        HStack {
            Text(name).font(.headline)
            engineMenu(for: name)
            Spacer()
            Button {
                agentTaskRole = name
                showAgentTask = true
            } label: {
                Label("작업 실행", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent).controlSize(.small)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    @ViewBuilder
    private func engineMenu(for name: String) -> some View {
        if let role = model.fullRoster.first(where: { $0.name == name }),
           role.mode != "marker", role.mode != "ghost" {
            Menu {
                ForEach(RepositoryAgentRole.supportedEngines, id: \.self) { engine in
                    Button {
                        model.setEngine(name, engine: engine)
                    } label: {
                        engineMenuLabel(engine, current: role.engine)
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "gearshape.2")
                    Text("엔진 \(engineDisplayName(role.engine))")
                }
                .font(.caption)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("클릭해 실행 엔진 변경 — 정의 개정판이 원장에 발행됩니다")
        }
    }

    @ViewBuilder
    private func editorCitations(_ document: LedgerDocument) -> some View {
        let citations = model.citationCards(of: document)
        if !citations.isEmpty {
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Text("인용한 근거").font(.callout.weight(.medium)).foregroundStyle(.secondary)
                ForEach(citations) { card in
                    citationCardRow(card, document: document)
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 8)
        }
    }

    private func citationCardRow(_ card: LedgerModel.CitationCard, document: LedgerDocument) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.caption).foregroundStyle(.secondary)
            Button((card.evidenceHead.title ?? "(무제)")
                .replacingOccurrences(of: "근거: ", with: "")) {
                model.area = .evidence
                model.selectedDocumentID = card.evidenceHead.id
            }
            .buttonStyle(.link)
            Text("(\(relLabel(card.rel)))")
                .font(.caption).foregroundStyle(.secondary)
            staleCitationBadge(card.stale)
            Button {
                model.detachCitation(from: document, evidenceID: card.citedID)
            } label: {
                Image(systemName: "xmark.circle").font(.caption)
            }
            .buttonStyle(.plain).foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private func editorReferences(_ document: LedgerDocument) -> some View {
        let references = model.references(to: document)
        if !references.isEmpty {
            Divider()
            TapDisclosure {
                ForEach(references) { reference in
                    Button(reference.title) { model.select(reference) }
                        .buttonStyle(.link)
                }
            } label: {
                Label("이 기록을 참조한 문서 \(references.count)", systemImage: "link")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20).padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private func engineMenuLabel(_ engine: String, current: String) -> some View {
        if engine == current {
            Label(engineDisplayName(engine), systemImage: "checkmark")
        } else {
            Text(engineDisplayName(engine))
        }
    }

    @ViewBuilder
    private func graphDocumentPane(_ document: LedgerDocument) -> some View {
        let isEvidence = document.head.author != "human" || document.head.effectiveType == "evidence"
        if isEvidence {
            EvidenceDetailView(model: model, document: document)
        } else {
            ScrollView {
                Text(document.head.body).padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func staleCitationBadge(_ stale: Bool) -> some View {
        if stale {
            Text("근거 갱신됨")
                .font(.caption2.bold())
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(.orange.opacity(0.2), in: Capsule())
                .foregroundStyle(.orange)
                .help("인용한 판 이후 근거가 개정됐습니다 — 내용 확인 필요")
        }
    }
}
