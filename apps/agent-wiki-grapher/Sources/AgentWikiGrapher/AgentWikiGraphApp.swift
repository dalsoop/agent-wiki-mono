import AppScaffoldKit
import DualEntryKit
import PermissionKit
import SingleInstanceKit
import StateRootKit
import SwiftUI

@main
struct AgentWikiGraphApp: App {
    @State private var model = AppModel()

    init() {
        DualEntryRules.exitIfMisusedFromIdentity()
        RanodeAppBootstrap.applyFleetDeskPolicy()
        HealthPulse.publish(app: "agent-wiki-graph")
        // MPM `--permission-bootstrap=` 은 2번째 인스턴스 — SingleInstance 예외.
        if !PermissionBootstrap.isRequested {
            SingleInstance.exitIfAlreadyRunning()
        }
        Task { @MainActor in
            _ = PermissionBootstrap.runIfRequested(appName: "AgentWikiGraph")
        }
    }

    var body: some Scene {
        // 일반 창 앱 — 실행하면 바로 주 창이 뜬다(메뉴바 없음, 독 아이콘 표시).
        // 콘텐츠·관리 앱의 기본 형태다. 상주 글랜스 유틸이면 --kind menubar 로 만들 것.
        Window("AgentWikiGraph", id: "main") {
            if PermissionBootstrap.isRequested {
                // 등록 전용 인스턴스 — 곧 terminate.
                Color.clear.frame(width: 1, height: 1)
            } else {
                MainView(model: model)
                    .gujoManaged()  // Cloud Apps 관리 게이트 — ship 검수가 채택을 요구한다.
            }
        }

        Settings {
            SettingsView(model: model)
                .frame(minWidth: 480, minHeight: 360)
        }
    }
}
