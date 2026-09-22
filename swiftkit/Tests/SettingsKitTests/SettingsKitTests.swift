import XCTest
@testable import SettingsKit

private struct Prefs: Codable, Equatable {
    var interval: Double
    var theme: String
}

final class SettingsStoreTests: XCTestCase {
    func testInMemoryRoundTripCodable() {
        let store = InMemorySettingsStore()
        store.write(Prefs(interval: 5, theme: "dark"), forKey: "prefs")
        XCTAssertEqual(store.read(Prefs.self, forKey: "prefs"), Prefs(interval: 5, theme: "dark"))
    }

    func testValueWithDefault() {
        let store = InMemorySettingsStore()
        XCTAssertEqual(store.value(forKey: "missing", default: 42), 42)
        store.write(7, forKey: "missing")
        XCTAssertEqual(store.value(forKey: "missing", default: 42), 7)
    }

    func testWriteNilDeletes() {
        let store = InMemorySettingsStore()
        store.write("x", forKey: "k")
        store.write(String?.none, forKey: "k")
        XCTAssertNil(store.read(String.self, forKey: "k"))
    }

    func testUserDefaultsBackendIsolatedBySuite() throws {
        let suite = "SettingsKitTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsSettingsStore(defaults)
        store.write(Prefs(interval: 1.5, theme: "light"), forKey: "p")
        XCTAssertEqual(store.read(Prefs.self, forKey: "p"), Prefs(interval: 1.5, theme: "light"))
    }
}

final class StoredWrapperTests: XCTestCase {
    func testStoredReadsDefaultThenPersists() throws {
        let suite = "StoredTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        @Stored(key: "interval", default: 5.0, defaults: defaults) var interval: Double
        XCTAssertEqual(interval, 5.0)      // 기본값
        interval = 12.5
        XCTAssertEqual(interval, 12.5)     // 저장 후 읽기
        // 새 래퍼 인스턴스도 같은 저장소에서 값을 본다.
        @Stored(key: "interval", default: 0.0, defaults: defaults) var reread: Double
        XCTAssertEqual(reread, 12.5)
    }
}
