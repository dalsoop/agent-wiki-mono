import XCTest
@testable import AgentScanKit

final class AgentScanKitTests: XCTestCase {
    func testKindFiltersNoise() {
        XCTAssertNil(AgentScanner.kind("/x/codex app-server --foo"))
        XCTAssertNil(AgentScanner.kind("/Applications/Foo.app/Contents/MacOS/claude"))
        XCTAssertEqual(AgentScanner.kind("/path/native-binary/claude --resume abc"), "claude")
        XCTAssertEqual(AgentScanner.kind("/usr/local/bin/codex exec"), "codex")
    }

    func testAppSlugSkipsMono() {
        XCTAssertNil(AgentScanner.appSlug("/w/apps/swift-app-mono"))
        XCTAssertEqual(AgentScanner.appSlug("/w/apps/pim-mail-swift/x"), "pim-mail-swift")
        XCTAssertNil(AgentScanner.appSlug("/w/no-apps-here"))
    }

    func testRepoDetectsMono() {
        XCTAssertEqual(AgentScanner.repo("/w/apps/swift-app-mono/y"), "swift-app-mono")
        XCTAssertNil(AgentScanner.repo("/w/apps/plain/y"))
    }

    func testRunReadsLargeOutputWithoutDeadlock() {
        // 파이프 버퍼(64KB) 초과 출력을 데드락 없이 다 읽는지 — 회귀 방지.
        let lines = AgentScanner.run("/bin/sh", ["-c", "for i in $(seq 1 5000); do echo line-$i-padding-padding-padding; done"])
        XCTAssertEqual(lines.count, 5000)
        XCTAssertEqual(lines.last, "line-5000-padding-padding-padding")
    }
}
