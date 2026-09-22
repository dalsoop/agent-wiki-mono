import XCTest
@testable import StateMirrorKit

/// 테스트가 **사용자의 실제 미러**에 쓰지 못하게 막는 계약.
///
/// 2026-08-10 실측: ADM 테스트의 픽스처가 `~/.swift-app-state/AppBuildManager.json`
/// 에 그대로 게시돼 있었다 — `root: /fixture/root-b` · `appCount: 1` ·
/// `sourceCheckError: cannot change to '/fixture/root-b'`. 미러를 읽는 소비자(GUI·에이전트·
/// 다른 앱)가 전부 거짓값을 받는 상태였다. 오버라이드 환경변수는 이미 있었지만 테스트가
/// 그걸 설정하는 걸 잊으면 그대로 새어나간다 — 그래서 kit 이 막는다.
final class StateMirrorTestIsolationTests: XCTestCase {

    private let home = "/Users/tester"

    func testXCTestRunnerNeverWritesToTheUserMirror() {
        for key in ["XCTestConfigurationFilePath", "XCTestSessionIdentifier", "XCTestBundlePath"] {
            let dir = StateMirror.directory(environment: [key: "/some/value"], homeDirectory: home)
            XCTAssertFalse(dir.hasPrefix(home), "\(key) 아래에서 사용자 미러에 쓰면 안 된다")
            XCTAssertTrue(dir.contains("swift-app-state-tests"))
        }
    }

    func testSwiftTestingRunnerIsAlsoIsolated() {
        let dir = StateMirror.directory(environment: ["SWIFT_TESTING_ENABLED": "1"], homeDirectory: home)
        XCTAssertFalse(dir.hasPrefix(home))
    }

    /// 명시 오버라이드가 최우선 — 테스트가 자기 임시 경로를 지정하면 그걸 쓴다.
    func testExplicitOverrideWinsOverTestIsolation() {
        let dir = StateMirror.directory(
            environment: ["SWIFT_APP_STATE_DIRECTORY": "/tmp/mine",
                          "XCTestConfigurationFilePath": "/x"],
            homeDirectory: home)
        XCTAssertEqual(dir, "/tmp/mine")
    }

    /// 실제 앱(테스트 아님)은 그대로 `~/.swift-app-state` — 격리가 프로덕션을 바꾸면 안 된다.
    func testProductionProcessStillUsesTheHomeMirror() {
        let dir = StateMirror.directory(environment: [:], homeDirectory: home)
        XCTAssertEqual(dir, home + "/.swift-app-state")
    }

    /// 이 테스트 프로세스 자신도 격리돼 있어야 한다(회귀의 실물 증거).
    func testThisVeryTestProcessIsIsolated() {
        XCTAssertFalse(StateMirror.dir.hasPrefix(NSHomeDirectory() + "/.swift-app-state"),
                       "테스트가 자기 실행 중에 사용자 미러를 가리키면 이미 샌 것이다")
    }
}
