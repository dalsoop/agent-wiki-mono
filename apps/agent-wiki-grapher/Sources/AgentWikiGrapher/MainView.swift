import SwiftUI
import AppKit

/// 주 창 — 도메인 화면으로 교체한다. 첫 실행은 사용법 온보딩(OnboardingView)이 대신 뜬다.
///
/// 계약 셋을 지킬 것(질책 이력 반영):
/// - 온보딩은 **사용법 소개만** — 질문형 데이터 입력 위저드 금지.
/// - CLI 에 추가하는 모든 연산은 GUI 표면(시트·컨텍스트 메뉴·행 액션)도 함께 — CLI 전용 금지.
/// - 상태 미러는 앱 시작 시 1회 게시(AppModel init) + 변경 지점마다 게시.
struct MainView: View {
    @Bindable var model: AppModel
    /// 사용법 온보딩은 한 번만.
    @AppStorage("hasSeenUsabilityOnboarding") private var hasSeenOnboarding = true

    var body: some View {
        Group {
            if !hasSeenOnboarding {
                OnboardingView(model: model) { hasSeenOnboarding = true }
            } else {
                content
            }
        }
        .frame(minWidth: 640, minHeight: 480)
    }

    private var content: some View {
        VStack(spacing: 12) {
            Text(model.status.isEmpty ? "—" : model.status)
                .font(.title2)
            Button(model.L(.menuRefresh)) { Task { await model.refresh() } }
        }
        .padding(24)
        .task { await model.refresh() }
    }
}
