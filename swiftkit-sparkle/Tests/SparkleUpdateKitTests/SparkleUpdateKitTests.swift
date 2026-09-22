import SwiftUI
import Testing
@testable import SparkleUpdateKit

/// SUFeedURL 이 없는 테스트 번들에서 FeedURL.current 는 nil 이어야 한다.
@Test func feedURLMissingWhenNotConfigured() {
    #expect(FeedURL.current == nil)
}

/// 설정 블록은 앱이 조립하지 않고 키트가 소유한다.
@MainActor
@Test func updateSectionAndCheckButtonArePublicViews() {
    _ = SparkleUpdateSection()
    _ = CheckForUpdatesButton()
    _ = EmptyView().withFleetUpdateSettings()
    _ = SparkleReceiveSettingsScene()
    _ = SparkleReceiveSettings.wrap(EmptyView())
    #expect(!SparkleL10n.t("sparkle.check_now").isEmpty)
    #expect(SparkleL10n.t("sparkle.check_now") != "sparkle.check_now")
    #expect(SparkleL10n.t("sparkle.open_settings") != "sparkle.open_settings")
}

/// 공개키도 마찬가지로 nil.
@Test func publicEDKeyMissingWhenNotConfigured() {
    #expect(FeedURL.publicEDKey == nil)
}
