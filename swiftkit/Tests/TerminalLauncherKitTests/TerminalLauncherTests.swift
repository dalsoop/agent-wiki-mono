import XCTest
@testable import TerminalLauncherKit

final class TerminalLauncherTests: XCTestCase {
    func testCommandFileIsZshScript() {
        let body = TerminalLauncher.commandFileContents(for: #"echo "hi""#)
        XCTAssertTrue(body.hasPrefix("#!/bin/zsh\n"))
        XCTAssertTrue(body.contains(#"echo "hi""#))
        XCTAssertFalse(body.localizedCaseInsensitiveContains("tell application"))
    }

    func testRunDelegatesToRunner() {
        var called = false
        let ok = TerminalLauncher.run("echo hi") { cmd in
            called = true
            XCTAssertEqual(cmd, "echo hi")
            return true
        }
        XCTAssertTrue(ok)
        XCTAssertTrue(called)
    }
}
