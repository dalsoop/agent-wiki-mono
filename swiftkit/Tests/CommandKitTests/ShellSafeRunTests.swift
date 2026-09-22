import XCTest
import Foundation
@testable import CommandKit

final class ShellSafeRunTests: XCTestCase {
    func testPositionalParametersBasic() {
        let r = ShellCommand.runSafe(
            scriptTemplate: "echo $1 $2",
            arguments: ["hello", "world"]
        )

        XCTAssertTrue(r.ok)
        XCTAssertEqual(r.trimmedStdout, "hello world")
    }

    func testInjectionWithSemicolonAndCommand() {
        let maliciousInput = "; echo INJECTED_EXECUTION ;"
        let r = ShellCommand.runSafe(
            scriptTemplate: "printf '%s' \"$1\"",
            arguments: [maliciousInput]
        )

        XCTAssertTrue(r.ok)
        // 세미콜론과 뒤이은 명령어가 셸에서 분리 실행되지 않고 단일 문자열 리터럴로 온전히 유지되어야 함
        XCTAssertEqual(r.stdout, maliciousInput)
    }

    func testInjectionWithSubshellAndBackticks() {
        let maliciousInput = "$(echo subshell_pwned) `echo backtick_pwned`"
        let r = ShellCommand.runSafe(
            scriptTemplate: "printf '%s' \"$1\"",
            arguments: [maliciousInput]
        )

        XCTAssertTrue(r.ok)
        XCTAssertEqual(r.stdout, maliciousInput)
    }

    func testInjectionWithPipesAndRedirects() {
        let maliciousInput = "foo | cat > /dev/null && false"
        let r = ShellCommand.runSafe(
            scriptTemplate: "printf '%s' \"$1\"",
            arguments: [maliciousInput]
        )

        XCTAssertTrue(r.ok)
        XCTAssertEqual(r.stdout, maliciousInput)
    }

    func testSpecialCharactersQuotesAndNewlines() {
        let arg1 = "'single' \"double\" \\backslash"
        let arg2 = "new\nline \t tab 🚀"

        let r = ShellCommand.runSafe(
            scriptTemplate: "printf '%s|%s' \"$1\" \"$2\"",
            arguments: [arg1, arg2]
        )

        XCTAssertTrue(r.ok)
        XCTAssertEqual(r.stdout, "\(arg1)|\(arg2)")
    }

    func testPositionalParametersAllExpansion() {
        let r = ShellCommand.runSafe(
            scriptTemplate: "for a in \"$@\"; do printf '[%s]' \"$a\"; done",
            arguments: ["first", "second with space", "third"]
        )

        XCTAssertTrue(r.ok)
        XCTAssertEqual(r.stdout, "[first][second with space][third]")
    }

    func testEmptyArgumentsList() {
        let r = ShellCommand.runSafe(
            scriptTemplate: "printf 'count=%d' \"$#\"",
            arguments: []
        )

        XCTAssertTrue(r.ok)
        XCTAssertEqual(r.stdout, "count=0")
    }

    func testCwdSupport() {
        let r = ShellCommand.runSafe(
            scriptTemplate: "pwd -P",
            arguments: [],
            cwd: "/private/tmp"
        )

        XCTAssertTrue(r.ok)
        XCTAssertEqual(r.trimmedStdout, "/private/tmp")
    }

    func testTimeoutSupport() {
        let r = ShellCommand.runSafe(
            scriptTemplate: "sleep 5",
            arguments: [],
            timeout: 0.05
        )

        XCTAssertTrue(r.timedOut)
        XCTAssertEqual(r.exitCode, 124)
        XCTAssertTrue(r.stderr.contains("timed out"))
    }
}
