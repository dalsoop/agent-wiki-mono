import AgentWikiGlobalCore
import AppScaffoldKit
import PermissionKit
import StateRootKit
import SwiftUI
import SingleInstanceKit

@main
struct AgentWikiGlobalApp: RanodeMenuBarExtraApp {
    static let service = "net.ranode.agent-wiki-global"
    static let productName = "AgentWikiGlobal"

    @State private var model = AppModel()

    init() {
        SingleInstance.exitIfAlreadyRunning()
        HealthPulse.publish(app: "agent-wiki-global")
        Task { @MainActor in
            _ = PermissionBootstrap.runIfRequested(appName: "AgentWikiGlobal")
        }
    }

    @ViewBuilder var menuContent: some View {
        if PermissionBootstrap.isRequested {
            EmptyView()
        } else {
            MenuBarView(model: model)
                .gujoManaged()
        }
    }

    @ViewBuilder var menuLabel: some View {
        Image(systemName: "app.dashed")
    }

    var settingsView: some View {
        SettingsView(model: model)
            .frame(minWidth: 480, minHeight: 360)
            .gujoManaged()
    }
}
