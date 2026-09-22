import SwiftUI
import KnowledgeBaseWikiUI
import KnowledgeBaseWikiCore
import NoticeBannerUIKit

/// 보조 CLI 패널 — monospaced forward. 메인 창은 원장 GUI.
struct CLIPanelView: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationSplitView {
            List(ReaderArea.allCases, selection: Binding(
                get: { model.area },
                set: { newValue in
                    guard let newValue else { return }
                    Task { await model.select(newValue) }
                }
            )) { area in
                Label(area.rawValue, systemImage: area.systemImage).tag(area)
            }
            .navigationSplitViewColumnWidth(min: 140, ideal: 160)
        } detail: {
            VStack(alignment: .leading, spacing: 0) {
                header
                Divider()
                if model.area == .pages { pageToolbar }
                if model.area == .graph { graphToolbar }
                if model.area == .evidence { evidenceToolbar }
                ErrorBanner(model.lastError, onDismiss: { model.lastError = "" })
                    .padding(.horizontal, 12)
                ScrollView {
                    Text(model.currentOutput.isEmpty ? model.L(.CLIPanelViewLabel) : model.currentOutput)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(12)
                }
            }
        }
        .frame(minWidth: 800, minHeight: 520)
        .task {
            await model.refresh()
            await model.select(model.area)
        }
    }

    private var header: some View {
        HStack {
            Text(model.L(.cliPanelTitle)).font(.headline)
            Text(model.L(.cliPanelAuxiliary)).font(.caption).padding(.horizontal, 6).padding(.vertical, 2)
                .background(.secondary.opacity(0.15), in: Capsule())
            Spacer()
            WikiWorldChooser(items: model.worldCatalog, selection: $model.world) {
                Task { await model.reloadCurrentArea() }
            }
            if WikiWorldPresentation.classify(name: model.world, rootPath: "") == .remoteShared {
                Button(model.L(.cliRemoteStatus)) { Task { await model.loadRemoteStatus() } }
                    .help(model.L(.CLIPanelViewHelp, GujoWikiWeb.projectURL))
            }
            Button {
                Task { await model.reloadCurrentArea() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help(model.L(.menuRefresh))
            if model.busy { ProgressView().controlSize(.small) }
        }
        .padding(12)
    }

    private var pageToolbar: some View {
        HStack(spacing: 8) {
            TextField(model.L(.CLIPanelViewTextfield), text: $model.pageQuery)
                .textFieldStyle(.roundedBorder)
                .onSubmit { Task { await model.showPage(model.pageQuery) } }
            Button(model.L(.actionSearch)) { Task { await model.searchPages() } }
            Button(model.L(.actionView)) { Task { await model.showPage(model.pageQuery) } }
            Button(model.L(.actionList)) { Task { await model.loadList() } }
            Button(model.L(.actionOnboarding)) { Task { await model.loadOnboarding() } }
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private var graphToolbar: some View {
        HStack(spacing: 8) {
            TextField(model.L(.CLIPanelViewTextfield_2), text: $model.graphQuery)
                .textFieldStyle(.roundedBorder)
                .onSubmit { Task { await model.showGraphNeighbors(model.graphQuery) } }
            Button(model.L(.actionNeighbors)) { Task { await model.showGraphNeighbors(model.graphQuery) } }
            Button(model.L(.actionTimeline)) { Task { await model.showGraphTimeline(model.graphQuery) } }
            Button(model.L(.actionStatus)) { Task { await model.loadGraphStatus() } }
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private var evidenceToolbar: some View {
        HStack(spacing: 8) {
            TextField(model.L(.CLIPanelViewTextfield_3), text: $model.evidenceQuery)
                .textFieldStyle(.roundedBorder)
                .onSubmit { Task { await model.showEvidence(model.evidenceQuery) } }
            Button(model.L(.actionLookup)) { Task { await model.showEvidence(model.evidenceQuery) } }
            Button(model.L(.actionList)) { Task { await model.loadEvidenceList() } }
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }
}
