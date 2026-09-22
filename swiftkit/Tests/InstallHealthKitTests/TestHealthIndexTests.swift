import Foundation
import XCTest
@testable import InstallHealthKit

/// "테스트가 컴파일이라도 되나" 를 재는 색인.
///
/// 실측 2026-08-11: business-people 테스트가 개명 리팩터 이후 몇 주째 컴파일조차 안 되는
/// 채 머지돼 있었는데 파이프라인도 doctor 도 전부 green 이었다. MR 에선 테스트가 안 돌고,
/// 야간 스윕은 `swift build` 만 하며(테스트 타깃 제외), doctor 에는 이 축이 없었다.
final class TestHealthIndexTests: XCTestCase {
    private func tempURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("test-health-\(UUID().uuidString).json")
    }

    func testRoundTrip() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        TestHealthIndex.write(
            ok: 120, withoutTests: 200,
            broken: [.init(app: "business-people-swift", error: "cannot find 'LedgerCLIKit' in scope")],
            at: url)

        let snapshot = try XCTUnwrap(TestHealthIndex.read(at: url))
        XCTAssertEqual(snapshot.ok, 120)
        XCTAssertEqual(snapshot.withoutTests, 200)
        XCTAssertEqual(snapshot.broken.first?.app, "business-people-swift")
        XCTAssertTrue(snapshot.broken.first?.error.contains("LedgerCLIKit") ?? false)
    }

    /// **색인이 없으면 "이상 없음" 이 아니라 "측정 안 됨" 이다.**
    /// 지금까지 못 잡은 이유가 정확히 그거다 — 아무도 재지 않은 축이 조용히 통과로 세어졌다.
    func testMissingIndexIsNotSuccess() {
        XCTAssertNil(TestHealthIndex.read(at: tempURL()))
    }

    /// 테스트가 없는 앱과 깨진 앱을 구분한다 — 섞으면 "테스트 0개" 를 건강으로 읽는다.
    func testWithoutTestsIsSeparateFromBroken() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        TestHealthIndex.write(ok: 10, withoutTests: 300, broken: [], at: url)
        let snapshot = try XCTUnwrap(TestHealthIndex.read(at: url))
        XCTAssertTrue(snapshot.broken.isEmpty)
        XCTAssertEqual(snapshot.withoutTests, 300)
    }

    /// 색인이 오래되면 그것도 신호다 — 스윕이 안 도는 걸 침묵으로 두지 않는다.
    func testAgeIsComputed() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let past = Date().addingTimeInterval(-30 * 24 * 3600)
        TestHealthIndex.write(ok: 1, withoutTests: 0, broken: [], at: url, now: past)
        let snapshot = try XCTUnwrap(TestHealthIndex.read(at: url))
        XCTAssertEqual(TestHealthIndex.ageInDays(of: snapshot), 30)
    }
}

/// 설정(`TestHealthConfig`) — UI 가 쓰고 scan 이 읽는다.
final class TestHealthConfigTests: XCTestCase {
    private func tempURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("thc-\(UUID().uuidString).json")
    }

    /// 기본은 보존 — 지우면 다음 스캔이 6~11시간이 걸린다(실측 2026-08-11).
    func testDefaultKeepsBuild() {
        let config = TestHealthConfig()
        XCTAssertTrue(config.keepBuild)
    }

    func testRoundTrip() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        var config = TestHealthConfig()
        config.keepBuild = false
        config.timeoutSeconds = 300
        config.save(at: url)

        let loaded = TestHealthConfig.load(at: url)
        XCTAssertEqual(loaded.keepBuild, false)
        XCTAssertEqual(loaded.timeoutSeconds, 300)
    }

    /// 파일이 없으면 기본 — 처음 설정을 연 사람도 보존으로 시작한다.
    func testMissingFileGivesDefault() {
        let loaded = TestHealthConfig.load(at: tempURL())
        XCTAssertTrue(loaded.keepBuild)
        XCTAssertEqual(loaded.timeoutSeconds, 900)
    }
}
