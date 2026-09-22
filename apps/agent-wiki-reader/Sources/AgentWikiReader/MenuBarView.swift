import SwiftUI
import MenuBarPopoverUIKit
import AppKit
import AppScaffoldKit

struct MenuBarView: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        StandardMenuBarPopover(
            width: 280,
            refreshTitle: model.L(.menuRefresh),
            settingsTitle: model.L(.menuSettings),
            quitTitle: model.L(.menuQuit),
            onRefresh: { await model.refresh() },
            onOpenSettings: { RanodeSettingsLink.open() },
            onQuit: { NSApplication.shared.terminate(nil) }
        ) {
            Text(model.L(.menuReportReader)).font(.caption).foregroundStyle(.secondary)
                        Text(model.status.isEmpty ? "—" : String(model.status.prefix(120)))
                            .font(.caption2.monospaced())
                            .lineLimit(4)
                            .frame(minWidth: 20)
                        Divider()
                        Button(model.L(.menuLedgerGUI)) { openWindow(id: "main") }
                        Button(model.L(.menuCLIPanel)) { openWindow(id: "cli") }
                        Button(model.L(.menuExternalMonolith)) { _ = model.openLedgerGUI() }
                        Button(model.L(.menuLoadOnboarding)) { Task { await model.loadOnboarding(); openWindow(id: "cli") } }
        }
        .task { await model.refresh() }
    }
}
