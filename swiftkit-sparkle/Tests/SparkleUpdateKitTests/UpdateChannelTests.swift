import Foundation
import Sparkle
import Testing
@testable import SparkleUpdateKit

/// 테스트마다 비어 있는 defaults suite 를 만든다.
private func freshDefaults() throws -> UserDefaults {
    let suite = "SparkleUpdateKitTests.UpdateChannel.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

@Test func defaultsKeyIsGujoUpdateChannel() {
    #expect(UpdateChannel.defaultsKey == "GujoUpdateChannel")
}

@Test func allowedChannelsIncludeLessUnstableChannels() {
    #expect(UpdateChannel.allowedSparkleChannels(for: .stable) == [])
    #expect(UpdateChannel.allowedSparkleChannels(for: .beta) == ["beta"])
    #expect(UpdateChannel.allowedSparkleChannels(for: .alpha) == ["beta", "alpha"])
    #expect(UpdateChannel.allowedSparkleChannels(for: .dev) == ["beta", "alpha", "dev"])
    #expect(UpdateChannel.dev.allowedSparkleChannels == ["beta", "alpha", "dev"])
}

@Test func unknownOrMissingValueIsStable() {
    #expect(UpdateChannel.parse(nil) == .stable)
    #expect(UpdateChannel.parse("") == .stable)
    #expect(UpdateChannel.parse("nightly") == .stable)
    #expect(UpdateChannel.parse(" Dev ") == .dev)
}

@Test func missingKeyReadsStable() throws {
    let defaults = try freshDefaults()
    #expect(UpdateChannel.current(in: defaults) == .stable)
}

@Test func unknownStoredValueReadsStable() throws {
    let defaults = try freshDefaults()
    defaults.set("canary", forKey: UpdateChannel.defaultsKey)
    #expect(UpdateChannel.current(in: defaults) == .stable)
}

@Test func setThenReadRoundTrips() throws {
    let defaults = try freshDefaults()
    for channel in UpdateChannel.allCases {
        UpdateChannel.set(channel, in: defaults)
        #expect(defaults.string(forKey: "GujoUpdateChannel") == channel.rawValue)
        #expect(UpdateChannel.current(in: defaults) == channel)
    }
}

/// 델리게이트는 매 확인 때 설정을 다시 읽는다.
@MainActor
@Test func delegateRereadsSettingOnEveryCheck() throws {
    let defaults = try freshDefaults()
    let delegate = UpdateChannelDelegate(defaults: defaults)
    let updater = SPUUpdater(
        hostBundle: Bundle.main,
        applicationBundle: Bundle.main,
        userDriver: SPUStandardUserDriver(hostBundle: Bundle.main, delegate: nil),
        delegate: nil
    )
    #expect(delegate.allowedChannels(for: updater) == [])
    UpdateChannel.set(.alpha, in: defaults)
    #expect(delegate.allowedChannels(for: updater) == ["beta", "alpha"])
    defaults.set("unknown", forKey: UpdateChannel.defaultsKey)
    #expect(delegate.allowedChannels(for: updater) == [])
}
