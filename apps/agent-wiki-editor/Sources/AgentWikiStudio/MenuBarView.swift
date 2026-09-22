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
            Text(model.L(.labelInternalStudio)).font(.caption).foregroundStyle(.secondary)
                        Text(model.status.isEmpty ? "—" : String(model.status.prefix(120)))
                            .font(.caption2.monospaced()).lineLimit(4)
                            .frame(minWidth: 20)
                        Divider()
                        Button(model.L(.buttonLedgerGui)) { openWindow(id: "main") }
                        Button(model.L(.windowCliPanel)) { openWindow(id: "cli") }
                        Button(model.L(.buttonExternalMonolith)) { _ = model.openLedgerGUI() }
        }
        .task { await model.refresh() }
    }
}
