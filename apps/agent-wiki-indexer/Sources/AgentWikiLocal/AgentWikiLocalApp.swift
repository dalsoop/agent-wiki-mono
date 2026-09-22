import AgentWikiLocalCore
import AppScaffoldKit
import DualEntryKit
import PermissionKit
import SingleInstanceKit
import StateRootKit
import SwiftUI

@main
struct AgentWikiLocalApp: RanodeMenuBarExtraApp {
    static let service = "net.ranode.agent-wiki-local"
    static let productName = "AgentWikiLocal"

    @State private var model = AppModel()

    init() {
        DualEntryRules.exitIfMisusedFromIdentity()
        RanodeAppBootstrap.applyFleetDeskPolicy()
        HealthPulse.publish(app: "agent-wiki-local")
        // MPM `--permission-bootstrap=` 은 2번째 인스턴스 — SingleInstance 예외.
        if !PermissionBootstrap.isRequested {
            SingleInstance.exitIfAlreadyRunning()
        }
        Task { @MainActor in
            _ = PermissionBootstrap.runIfRequested(appName: "AgentWikiLocal")
        }
    }

        @ViewBuilder var menuContent: some View {
        if PermissionBootstrap.isRequested {
                        // 등록 전용 인스턴스 — 곧 terminate.
                        EmptyView()
                    } else {
                        MenuBarView(model: model)
                    }
    }

    @ViewBuilder var menuLabel: some View {
        Image(systemName: "app.dashed")
    }

    var settingsView: some View {
        SettingsView(model: model)
            .frame(minWidth: 480, minHeight: 360)
    }

}
