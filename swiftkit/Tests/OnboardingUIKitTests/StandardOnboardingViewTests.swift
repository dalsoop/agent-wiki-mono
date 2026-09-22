import XCTest
import SwiftUI
import LocalizationKit
import OnboardingKit
@testable import OnboardingUIKit

final class StandardOnboardingViewTests: XCTestCase {

    func testPresetItems() {
        let fda = OnboardingItem.fullDiskAccess(done: false)
        XCTAssertEqual(fda.id, "fullDiskAccess")
        XCTAssertFalse(fda.done)
        XCTAssertTrue(fda.required)
        XCTAssertNotNil(fda.title)
        XCTAssertNotNil(fda.detail)
        XCTAssertEqual(fda.symbol, "internaldrive")

        let ax = OnboardingItem.accessibility(done: true)
        XCTAssertEqual(ax.id, "accessibility")
        XCTAssertTrue(ax.done)
        XCTAssertTrue(ax.required)

        let screen = OnboardingItem.screenRecording(done: false)
        XCTAssertEqual(screen.id, "screenRecording")
        XCTAssertFalse(screen.done)

        let defs = OnboardingItem.defaults(done: true)
        XCTAssertEqual(defs.id, "defaults")
        XCTAssertTrue(defs.done)
        XCTAssertFalse(defs.required)

        let req = OnboardingItem.required(done: false)
        XCTAssertEqual(req.id, "required")
        XCTAssertFalse(req.done)
        XCTAssertTrue(req.required)

        let feat = OnboardingItem.feature(symbol: "star", title: "Star Feature", detail: "Detail")
        XCTAssertEqual(feat.symbol, "star")
        XCTAssertEqual(feat.title, "Star Feature")
        XCTAssertTrue(feat.done)
        XCTAssertFalse(feat.required)
    }

    @MainActor
    func testCanFinishLogic() {
        let incompleteView = StandardOnboardingView(
            items: [
                .defaults(done: true),
                .required(done: false)
            ],
            onComplete: {}
        )
        XCTAssertFalse(incompleteView.canFinish)

        let completeView = StandardOnboardingView(
            items: [
                .defaults(done: true),
                .required(done: true)
            ],
            onComplete: {}
        )
        XCTAssertTrue(completeView.canFinish)

        let optionalOnlyView = StandardOnboardingView(
            items: [
                .defaults(done: true),
                OnboardingItem(id: "opt", done: false, required: false)
            ],
            onComplete: {}
        )
        XCTAssertTrue(optionalOnlyView.canFinish)
    }

    func testLocalization() {
        let koSub = OnboardingUIKitL10n.string("onboarding.subtitle.default", language: .korean)
        XCTAssertEqual(koSub, "앱이 바로 동작하도록 필요한 설정을 지금 끝냅니다.")

        let enSub = OnboardingUIKitL10n.string("onboarding.subtitle.default", language: .english)
        XCTAssertEqual(enSub, "Complete the necessary setup to get started right away.")

        let koBtn = OnboardingUIKitL10n.string("onboarding.button.start", language: .korean)
        XCTAssertEqual(koBtn, "시작하기")

        let enBtn = OnboardingUIKitL10n.string("onboarding.button.start", language: .english)
        XCTAssertEqual(enBtn, "Get Started")

        let koFda = OnboardingUIKitL10n.string("onboarding.item.full_disk_access.title", language: .korean)
        XCTAssertEqual(koFda, "전체 디스크 접근 권한")

        let enFda = OnboardingUIKitL10n.string("onboarding.item.full_disk_access.title", language: .english)
        XCTAssertEqual(enFda, "Full Disk Access")
    }

    @MainActor
    func testStandardOnboardingViewInit() {
        var completed = false
        var skipped = false

        let view = StandardOnboardingView(
            title: "TestApp",
            subtitle: "Subtitle",
            items: [
                .fullDiskAccess(done: true),
                .accessibility(done: true)
            ],
            onSkip: { skipped = true },
            onComplete: { completed = true }
        )

        XCTAssertEqual(view.title, "TestApp")
        XCTAssertEqual(view.subtitle, "Subtitle")
        XCTAssertTrue(view.canFinish)

        view.onSkip?()
        XCTAssertTrue(skipped)

        view.onComplete()
        XCTAssertTrue(completed)
    }
}
