import XCTest
@testable import PrivilegedKit
import CommandKit

final class PrivilegedKitTests: XCTestCase {
    func testInvocationRunsShell() {
        let (path, args) = PrivilegedRunner.invocation(for: ["a", "b"], asRoot: false)
        XCTAssertEqual(path, "/bin/sh")
        XCTAssertEqual(args, ["-c", "a && b"])
    }

    func testInvocationAsRootRunsShellDirectly() {
        let (path, args) = PrivilegedRunner.invocation(for: ["a", "b"], asRoot: true)
        XCTAssertEqual(path, "/bin/sh")
        XCTAssertEqual(args, ["-c", "a && b"])
    }

    func testInjectedRunnerSeesShellNotAppleEvents() async {
        final class SpyRunner: CommandRunning, @unchecked Sendable {
            var path = ""
            var args: [String] = []
            func run(_ launchPath: String, _ arguments: [String], timeout: TimeInterval?) async -> CommandResult {
                path = launchPath
                args = arguments
                return CommandResult(stdout: "", stderr: "", exitCode: 0)
            }
        }
        let spy = SpyRunner()
        let r = await PrivilegedRunner(runner: spy).run(["wg-quick up wg0"])
        XCTAssertTrue(r.ok)
        XCTAssertEqual(spy.path, "/bin/sh")
        XCTAssertEqual(spy.args, ["-c", "wg-quick up wg0"])
    }

    func testEmptyCommandsReturnsErrorWithoutRunning() async {
        final class SpyRunner: CommandRunning, @unchecked Sendable {
            var called = false
            func run(_ launchPath: String, _ arguments: [String], timeout: TimeInterval?) async -> CommandResult {
                called = true
                return CommandResult(stdout: "", stderr: "", exitCode: 0)
            }
        }
        let spy = SpyRunner()
        let r = await PrivilegedRunner(runner: spy).run([])
        XCTAssertEqual(r.exitCode, 1)
        XCTAssertFalse(spy.called)
    }
}
