import SwiftUI
import WindowChromeKit
import KnowledgeBaseWikiUI
import KnowledgeBaseWikiCore
import NoticeBannerUIKit

struct MainWindowView: View {
    @Bindable var model: AppModel

    var body: some View {
        TwoColumnCatalog {
            List(StudioArea.allCases, selection: Binding(
                get: { model.area },
                set: { newValue in
                    guard let newValue else { return }
                    Task { await model.select(newValue) }
                }
            )) { area in
                Label(area.rawValue, systemImage: area.systemImage).tag(area)
            }
        } detail: {
            VStack(alignment: .leading, spacing: 0) {
                header
                Divider()
                if model.area == .publish { publishPanel }
                ErrorBanner(model.lastError, onDismiss: { model.lastError = "" })
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        Text(model.output.isEmpty ? model.L(.MainWindowViewText) : model.output)
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(12)
                    }
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
            Text(model.L(.windowCliPanel)).font(.headline)
            Text(model.L(.badgeAuxiliary)).font(.caption).padding(.horizontal, 6).padding(.vertical, 2)
                .background(.secondary.opacity(0.15), in: Capsule())
            Spacer()
            WikiWorldChooser(items: model.worldCatalog, selection: $model.world) {
                Task { await model.reloadCurrentArea() }
            }
            if WikiWorldPresentation.classify(name: model.world, rootPath: "") == .remoteShared {
                Button(model.L(.cliRemoteStatus)) { Task { await model.loadRemoteStatus() } }
                    .help(model.L(.MainWindowViewHelp, GujoWikiWeb.projectURL))
            }
            Button {
                Task { await model.reloadCurrentArea() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help(model.L(.menuRefresh))
            Button(model.L(.buttonExternalMonolith)) { _ = model.openLedgerGUI() }
                .help(model.L(.helpExternalMonolith))
            if model.busy { ProgressView().controlSize(.small) }
        }
        .padding(12)
    }

    private var publishPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(model.L(.title), text: $model.publishTitle)
                .textFieldStyle(.roundedBorder)
            TextEditor(text: $model.publishBody)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 100, maxHeight: 160)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
            HStack {
                Button(model.L(.buttonCliGuide)) { model.showPublishCLIHint() }
                Button(model.L(.buttonPublishRun)) { Task { await model.publishNow() } }
                    .keyboardShortcut(.return, modifiers: [.command])
                Spacer()
                Text(model.L(.hintFullCli))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
