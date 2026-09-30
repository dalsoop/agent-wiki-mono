import OnboardingUIKit
import SwiftUI

/// 사용법 소개. 첫 실행 게이트가 아니다 — 필수 설정이 있을 때만 설정 온보딩을 단다.
/// 기능이 자리를 잡으면 카드 문구를 실제 사용법으로 바꾼다.
struct OnboardingView: View {
    @Bindable var model: AppModel
    var onStart: () -> Void

    var body: some View {
        OnboardingIntroView(
            title: "AgentWikiGraph",
            subtitle: model.L(.onboardingSubtitle),
            features: [
                .init(
                    symbol: "cursorarrow.click",
                    title: model.L(.onboardingFeatureStartTitle),
                    detail: model.L(.onboardingFeatureStartDetail)
                ),
                .init(
                    symbol: "terminal",
                    title: model.L(.onboardingFeatureCliTitle),
                    detail: model.L(.onboardingFeatureCliDetail)
                ),
                .init(
                    symbol: "app.badge.checkmark",
                    title: model.L(.onboardingFeatureEntitlementTitle),
                    detail: model.L(.onboardingFeatureEntitlementDetail)
                ),
            ],
        note: model.L(.onboardingPrivacyNote),
            startTitle: model.L(.onboardingStart),
            onStart: onStart
        )
    }

}
