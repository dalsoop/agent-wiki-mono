import XCTest
@testable import LocalizationKit

@MainActor
final class LocalizationKitTests: XCTestCase {
    private func makeManager() -> LocalizationManager {
        // 테스트마다 격리된 UserDefaults suite (영속 상태 간섭 방지).
        let suite = UserDefaults(suiteName: "LocalizationKitTests.\(UUID().uuidString)")!
        return LocalizationManager(baseBundle: .module, defaultsKey: "lang", userDefaults: suite)
    }

    func testKoreanString() {
        let m = makeManager()
        m.setLanguage(.korean)
        XCTAssertEqual(m.string("greeting"), "안녕")
    }

    func testEnglishString() {
        let m = makeManager()
        m.setLanguage(.english)
        XCTAssertEqual(m.string("greeting"), "Hello")
    }

    func testMissingKeyReturnsKey() {
        let m = makeManager()
        m.setLanguage(.english)
        XCTAssertEqual(m.string("nope.missing"), "nope.missing")
    }

    func testRelativeTimeBuckets() {
        let now = Date()
        XCTAssertEqual(RelativeTime.bucket(nil, now: now), .none)
        XCTAssertEqual(RelativeTime.bucket(now.addingTimeInterval(-30), now: now), .seconds(30))
        XCTAssertEqual(RelativeTime.bucket(now.addingTimeInterval(60), now: now), .justNow)
    }

    func testAppLocalizationForwardsLanguageChange() {
        let suite = UserDefaults(suiteName: "LocalizationKitTests.\(UUID().uuidString)")!
        let loc = AppLocalization(baseBundle: .module, defaultsKey: "lang", userDefaults: suite)
        loc.setLanguage(.korean)
        XCTAssertEqual(loc.string("greeting"), "안녕")
        loc.setLanguage(.english)
        XCTAssertEqual(loc.string("greeting"), "Hello")
    }

    func testLocalizationKeyOverload() {
        enum Key: String, LocalizationKey { case greeting }
        let suite = UserDefaults(suiteName: "LocalizationKitTests.\(UUID().uuidString)")!
        let loc = AppLocalization(baseBundle: .module, defaultsKey: "lang", userDefaults: suite)
        loc.setLanguage(.english)
        XCTAssertEqual(loc.string(Key.greeting), "Hello")
        XCTAssertEqual(loc.string(Key.greeting, "x"), "Hello")
    }
}
