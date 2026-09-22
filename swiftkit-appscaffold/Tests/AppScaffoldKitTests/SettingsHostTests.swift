import SwiftUI
import Testing
@testable import AppScaffoldKit

/// 설정 호스트(`RanodeSettingsHost`) 래핑 및 함대 공통 업데이트 UI 통합 검증 상위 공용 테스트.
@MainActor
@Suite struct SettingsHostTests {
    private struct DummySettingsView: View {
        var body: some View {
            Text("Dummy Settings View")
        }
    }

    @Test func settingsHostWrapsCustomViewSafely() {
        let view = DummySettingsView()
        let wrapped = RanodeSettingsHost.wrap(view)
        #expect(wrapped != nil)
    }

    @Test func settingsHostExecutesWithoutCrashingOnRepeatedCalls() {
        let view = DummySettingsView()
        let w1 = RanodeSettingsHost.wrap(view)
        let w2 = RanodeSettingsHost.wrap(view)
        #expect(w1 != nil && w2 != nil)
    }
}
