import AppKit
import AppScaffoldKit
import KnowledgeBaseWikiCore
import SwiftUI

/// 원장 LedgerArea 메인 창 본문 (monlith · Reader · Studio 공통).
public struct AgentWikiRootView: View {
    @Bindable public var session: AgentWikiSession
    @AppStorage(Onboarding.welcomeCompletedKey) private var welcomeCompleted = false
    @State private var showWelcome = false
    @State private var surfaceEpoch = 0

    public init(session: AgentWikiSession) {
        self.session = session
    }

    public var body: some View {
        VStack(spacing: 0) {
            // monlith CUTOFF — 호환 배너 제거. Reader/Studio 만 제품 창.
            LedgerView(model: session.model)
                .frame(minWidth: 860, minHeight: 540)
                .gujoManaged()
        }
        .onAppear {
            session.applySurfaceClamp()
            surfaceEpoch &+= 1
            // monlith 컷오프 후: fixedSurface=nil 은 개발/테스트 호스트만. 온보딩은 surface 고정 제품에서 불필요.
            if session.fixedSurface == nil, !welcomeCompleted { showWelcome = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // fixedSurface 가 있으면 그 값으로, 없으면 파일/env 재읽기
            session.applySurfaceClamp()
            surfaceEpoch &+= 1
        }
        .sheet(isPresented: $showWelcome) {
            WelcomeOnboardingView {
                welcomeCompleted = true
                showWelcome = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .agentWikiShowWelcomeOnboarding)) { _ in
            NSApp.activate(ignoringOtherApps: true)
            for window in NSApp.windows where window.canBecomeKey {
                window.makeKeyAndOrderFront(nil)
                break
            }
            showWelcome = true
        }
    }

}

/// 설정 탭 묶음 (세션 모델 공유).
public struct AgentWikiSettingsRoot: View {
    @Bindable public var session: AgentWikiSession

    public init(session: AgentWikiSession) {
        self.session = session
    }

    public var body: some View {
        TabView {
            LedgerSettingsView(model: session.model)
                .tabItem { Label("일반", systemImage: "gearshape") }
            FleetSettingsView()
                .tabItem { Label("Fleet", systemImage: "point.3.connected.trianglepath.dotted") }
            SchedulerView()
                .tabItem { Label("스케줄러", systemImage: "clock.arrow.2.circlepath") }
            AgentIntegrationView()
                .tabItem { Label("에이전트 연동", systemImage: "link") }
            BackupSettingsView(model: session.model)
                .tabItem { Label("백업", systemImage: "externaldrive.badge.timemachine") }
        }
        .frame(width: 600, height: 520)
    }
}
