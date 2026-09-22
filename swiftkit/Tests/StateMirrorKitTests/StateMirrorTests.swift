import XCTest
@testable import StateMirrorKit

/// StateMirror 는 게시만 있고 정리가 없었다 — 앱이 끝난 뒤에도 마지막 상태가 파일로 남아
/// 소비자가 그걸 현재 사실로 읽었다(MenuFold 도그푸딩에서 발견). `clear` 의 계약을 고정한다.
final class StateMirrorTests: XCTestCase {
    private struct Sample: Codable, Equatable { let fold: String }

    /// 테스트가 실제 홈의 미러를 건드리지 않도록 고유한 앱 이름을 쓴다.
    private var appName: String { "StateMirrorTests-\(UUID().uuidString)" }

    private func read(_ app: String) -> [String: Any]? {
        guard let data = FileManager.default.contents(atPath: StateMirror.path(app: app)) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    func testDirectoryUsesExplicitEnvironmentOverride() {
        XCTAssertEqual(
            StateMirror.directory(
                environment: ["SWIFT_APP_STATE_DIRECTORY": "/tmp/isolated-state"],
                homeDirectory: "/Users/example"
            ),
            "/tmp/isolated-state"
        )
    }

    func testDirectoryFallsBackToHomeStateDirectory() {
        XCTAssertEqual(
            StateMirror.directory(environment: [:], homeDirectory: "/Users/example"),
            "/Users/example/.swift-app-state"
        )
    }

    func testPublishWritesEnvelopeAtDeclaredPath() throws {
        let app = appName
        defer { StateMirror.clear(app: app) }

        StateMirror.publish(app: app, Sample(fold: "collapsed"))

        let object = try XCTUnwrap(read(app), "게시한 미러를 path(app:) 에서 못 읽었다")
        XCTAssertEqual(object["app"] as? String, app)
        XCTAssertNotNil(object["updatedAt"], "updatedAt 이 없으면 health.freshness 가 성립하지 않는다")
        XCTAssertEqual((object["state"] as? [String: Any])?["fold"] as? String, "collapsed")
    }

    func testClearRemovesMirrorSoConsumersSeeNoStaleState() {
        let app = appName
        StateMirror.publish(app: app, Sample(fold: "collapsed"))
        XCTAssertNotNil(read(app), "사전 조건: 미러가 있어야 한다")

        StateMirror.clear(app: app)

        XCTAssertNil(read(app), "clear 후에도 미러가 남으면 소비자가 낡은 상태를 현재로 읽는다")
        XCTAssertFalse(FileManager.default.fileExists(atPath: StateMirror.path(app: app)))
    }

    /// 앱이 한 번도 게시하지 않고 종료해도 terminate 훅은 성공해야 한다. "크래시 안 함" 만으로는
    /// 부족하다 — clear 가 빈 파일이나 디렉터리를 만들어 두면 소비자가 그걸 게시로 읽는다.
    func testClearOfAnUnpublishedAppLeavesNoMirrorBehind() {
        let app = appName
        XCTAssertFalse(FileManager.default.fileExists(atPath: StateMirror.path(app: app)), "사전 조건")

        StateMirror.clear(app: app)
        StateMirror.clear(app: app)   // 종료 훅이 두 번 불려도 같아야 한다

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: StateMirror.path(app: app)),
            "clear 가 빈 미러를 만들면 소비자가 없는 상태를 현재로 읽는다")
        XCTAssertNil(read(app))
    }

    func testPublishAfterClearRepublishes() throws {
        let app = appName
        defer { StateMirror.clear(app: app) }

        StateMirror.publish(app: app, Sample(fold: "expanded"))
        StateMirror.clear(app: app)
        StateMirror.publish(app: app, Sample(fold: "collapsed"))   // 앱 재실행 시나리오

        let object = try XCTUnwrap(read(app))
        XCTAssertEqual((object["state"] as? [String: Any])?["fold"] as? String, "collapsed")
    }
}
