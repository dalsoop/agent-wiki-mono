import SwiftUI
import MenuBarPopoverUIKit
import AppScaffoldKit
import AppKit

struct MenuBarView: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        StandardMenuBarPopover(
            width: 240,
            refreshTitle: model.L(.menuRefresh),
            settingsTitle: model.L(.menuSettings),
            quitTitle: model.L(.menuQuit),
            onRefresh: { await model.refresh() },
            onOpenSettings: { RanodeSettingsLink.open() },
            onQuit: { NSApplication.shared.terminate(nil) }
        ) {
            Text(model.status.isEmpty ? "—" : model.status)
                            .font(.callout)
        }
        .task { await model.refresh() }
    }
}
