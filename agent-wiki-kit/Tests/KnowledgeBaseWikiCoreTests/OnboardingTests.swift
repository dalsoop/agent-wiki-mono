import Foundation
import Testing
@testable import KnowledgeBaseWikiCore

@Suite struct OnboardingTests {
    @Test func welcomeCompletedKeyIsStable() {
        #expect(Onboarding.welcomeCompletedKey == "agentWikiWelcomeCompleted")
    }

    @Test func cliStatusReflectsResolvePath() {
        let st = Onboarding.cliStatus()
        // 이 머신에 agent-wiki 가 있으면 ok, 없어도 구조화 힌트는 있어야 한다.
        if st.ok {
            #expect(!st.detail.isEmpty)
            #expect(st.hint == nil)
        } else {
            #expect(st.hint?.contains("app-build-manager") == true
                    || st.hint?.contains("ship") == true)
        }
    }

    @Test func skillStatusUsesAgentSurface() {
        let st = Onboarding.skillStatus()
        // status API 는 크래시 없이 끝나야 한다. ok 여부는 홈 상태 의존.
        if st.ok {
            #expect(st.detail.contains("부착") || !st.detail.isEmpty)
        } else {
            #expect(st.hint != nil || st.detail.isEmpty)
        }
    }

    @Test func dualEntryStatusDoesNotThrow() {
        let st = Onboarding.dualEntryStatus()
        _ = st.ok
        _ = st.detail
        _ = st.hint
    }
}
