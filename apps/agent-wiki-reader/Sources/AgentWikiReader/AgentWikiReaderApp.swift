import AppScaffoldKit
import DualEntryKit
import KnowledgeBaseWikiUI
import PermissionKit
import SingleInstanceKit
import StateRootKit
import SwiftUI

@main
struct AgentWikiReaderApp: App {
    @State private var model = AppModel()
    /// 인프로세스 원장 GUI — surface=reader 고정 (monlith open 불필요).
    @State private var ledgerSession = AgentWikiSession(fixedSurface: "reader")

    init() {
        DualEntryRules.exitIfMisusedFromIdentity()
        RanodeAppBootstrap.applyFleetDeskPolicy()
        HealthPulse.publish(app: "agent-wiki-reader")
        if !PermissionBootstrap.isRequested {
            SingleInstance.exitIfAlreadyRunning()
        }
        Task { @MainActor in
            _ = PermissionBootstrap.runIfRequested(appName: "AgentWikiReader")
        }
    }

    var body: some Scene {
        MenuBarExtra("Wiki Reader", systemImage: "book") {
            if PermissionBootstrap.isRequested {
                EmptyView()
            } else {
                MenuBarView(model: model)
            }
        }
        .menuBarExtraStyle(.window)

        // WindowGroup 이라 실행 시 원장 창이 바로 뜬다 (MenuBar-only 함정 방지).
        // LSUIElement + 이전 세션 창 닫힘 상태면 창 0개로 뜨는 함정 → presented 강제.
        WindowGroup("Agent Wiki Reader", id: "main") {
            if PermissionBootstrap.isRequested {
                Color.clear.frame(width: 1, height: 1)
            } else {
                AgentWikiRootView(session: ledgerSession)
                    .gujoManaged()
            }
        }
        .defaultSize(width: 960, height: 640)
        .defaultLaunchBehavior(.presented)

        Window(model.L(.windowCLIPanel), id: "cli") {
            if PermissionBootstrap.isRequested {
                Color.clear.frame(width: 1, height: 1)
            } else {
                CLIPanelView(model: model)
                    .gujoManaged()
            }
        }
        .defaultSize(width: 800, height: 560)

        Settings {
            if PermissionBootstrap.isRequested {
                Color.clear.frame(width: 1, height: 1)
            } else {
                // 원장 설정 + 앱 설정
                TabView {
                    AgentWikiSettingsRoot(session: ledgerSession)
                        .tabItem { Label(model.L(.tabLedger), systemImage: "books.vertical") }
                    SettingsView(model: model)
                        .tabItem { Label(model.L(.tabApp), systemImage: "gearshape") }
                }
                .frame(minWidth: 600, minHeight: 480)
                .gujoManaged()
            }
        }
    }
}
