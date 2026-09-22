import XCTest
@testable import AppPathsKit

/// 창에서 못 닿는 경로를 **열기 전에** 알아야 한다 — 열면 돌아오지 않는다.
final class PrivacyReachTests: XCTestCase {
    private var home: String!

    override func setUpWithError() throws {
        home = NSTemporaryDirectory() + "reach-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: home)
    }

    func testProtectedTopLevelDirectories() {
        XCTAssertTrue(PrivacyReach.isProtected(home + "/Documents/a.md", home: home))
        XCTAssertTrue(PrivacyReach.isProtected(home + "/Desktop/a.md", home: home))
        XCTAssertFalse(PrivacyReach.isProtected(home + "/.codex/skills/a/SKILL.md", home: home))
        XCTAssertFalse(PrivacyReach.isProtected("/opt/x/a.md", home: home))
    }

    /// 이름이 비슷한 디렉터리에 속지 않는다 — `DocumentsBackup` 은 보호 대상이 아니다.
    func testSimilarNamesAreNotProtected() {
        XCTAssertFalse(PrivacyReach.isProtected(home + "/DocumentsBackup/a.md", home: home))
    }

    /// **디렉터리가 심볼릭**이면 마지막 조각만 풀어선 못 잡는다(실측 모양).
    func testSymlinkedDirectoryResolves() throws {
        let link = home + "/skill-dir"
        try FileManager.default.createSymbolicLink(
            atPath: link, withDestinationPath: home + "/Documents/whatever")
        XCTAssertTrue(PrivacyReach.isProtected(link + "/SKILL.md", home: home))
    }

    /// CLI 는 터미널 권한을 물려받아 막히지 않는다 — 같은 경로라도 답이 다르다.
    func testOnlyWindowedProcessesAreBlocked() {
        let path = home + "/Documents/a.md"
        XCTAssertTrue(PrivacyReach.mayBlock(path, home: home, windowed: true))
        XCTAssertFalse(PrivacyReach.mayBlock(path, home: home, windowed: false))
    }
}
