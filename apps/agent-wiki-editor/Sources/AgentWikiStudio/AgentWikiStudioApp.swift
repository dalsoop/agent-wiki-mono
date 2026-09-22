import AppScaffoldKit
import AgentWikiStudioCore
import DualEntryKit
import KnowledgeBaseWikiUI
import PermissionKit
import SingleInstanceKit
import StateRootKit
import SwiftUI

@main
struct AgentWikiStudioApp: App {
    @State private var model = AppModel()
    @State private var ledgerSession = AgentWikiSession(fixedSurface: "studio")

    init() {
        DualEntryRules.exitIfMisusedFromIdentity()
        RanodeAppBootstrap.applyFleetDeskPolicy()
        if !PermissionBootstrap.isRequested {
            SingleInstance.exitIfAlreadyRunning()
            HealthPulse.publish(app: "agent-wiki-studio")
        }
        let m = model
        Task { @MainActor in
            _ = PermissionBootstrap.runIfRequested(appName: "AgentWikiStudio")
            // 런치 시 상태 미러 1회 게시 — MenuBarExtra 내용물은 열기 전엔 만들어지지
            // 않아 .task 의 refresh 가 안 돌면, 조작이 없는 날엔 미러가 계속 옛 날짜다.
            await m.refresh()
        }
    }

    var body: some Scene {
        MenuBarExtra("Wiki Studio", systemImage: "pencil.and.outline") {
            studioWhenReady { MenuBarView(model: model) }
        }
        .menuBarExtraStyle(.window)

        // WindowGroup: 실행 시 원장 GUI 즉시 (MenuBar-only 함정 방지).
        // LSUIElement + 이전 세션 창 닫힘 상태면 창 0개로 뜨는 함정 → presented 강제.
        WindowGroup("Agent Wiki Studio", id: "main") {
            studioWhenReady {
                AgentWikiRootView(session: ledgerSession)
                    .gujoManaged()
            }
        }
        .defaultSize(width: 960, height: 640)
        .defaultLaunchBehavior(.presented)

        Window(model.L(.windowCliPanel), id: "cli") {
            studioWhenReady { MainWindowView(model: model).gujoManaged() }
        }
        .defaultSize(width: 800, height: 560)

        Settings {
            studioWhenReady { settingsTabs }
        }
    }

    @ViewBuilder
    private func studioWhenReady<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if PermissionBootstrap.isRequested {
            EmptyView()
        } else {
            content()
        }
    }

    private var settingsTabs: some View {
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
