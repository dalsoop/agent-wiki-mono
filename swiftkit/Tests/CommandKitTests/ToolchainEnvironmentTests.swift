import XCTest
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
@testable import CommandKit

/// 오염된 `SWIFT_EXEC` 가 자식 프로세스로 새면 자식의 SwiftPM 빌드가 죽는다.
/// 문자열 검사가 아니라 **실제로 자식을 띄워** 값이 안 보이는지 본다.
final class ToolchainEnvironmentTests: XCTestCase {

    // MARK: - 판정

    func testInterpreterDriverIsUnusable() {
        XCTAssertTrue(ToolchainEnvironment.isUnusableSwiftExec("/usr/bin/swift"))
        XCTAssertTrue(ToolchainEnvironment.isUnusableSwiftExec("swift"))
        XCTAssertTrue(
            ToolchainEnvironment.isUnusableSwiftExec(
                "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift"))
    }

    func testEmptyValueIsUnusable() {
        XCTAssertTrue(ToolchainEnvironment.isUnusableSwiftExec(""))
        XCTAssertTrue(ToolchainEnvironment.isUnusableSwiftExec("   "))
    }

    /// 넓게 지우면 이 정화 자체가 새 함정이 된다 — 일부러 넣은 컴파일러는 살려둔다.
    func testRealCompilerIsLeftAlone() {
        XCTAssertFalse(ToolchainEnvironment.isUnusableSwiftExec("/usr/bin/swiftc"))
        XCTAssertFalse(ToolchainEnvironment.isUnusableSwiftExec("swiftc"))
        XCTAssertFalse(ToolchainEnvironment.isUnusableSwiftExec("/opt/toolchain/bin/swiftc-wrapper"))
    }

    // MARK: - 정화

    func testSanitizedDropsKeyRatherThanBlanking() {
        let env = ToolchainEnvironment.sanitized(["SWIFT_EXEC": "/usr/bin/swift", "PATH": "/bin"])
        // 빈 문자열로 남기면 SwiftPM 이 그걸 경로로 읽는다 — 키 자체가 없어야 한다.
        XCTAssertNil(env["SWIFT_EXEC"])
        XCTAssertEqual(env["PATH"], "/bin")
    }

    func testSanitizedKeepsUsableValueAndEverythingElse() {
        let env = ToolchainEnvironment.sanitized(["SWIFT_EXEC": "/usr/bin/swiftc", "HOME": "/tmp"])
        XCTAssertEqual(env["SWIFT_EXEC"], "/usr/bin/swiftc")
        XCTAssertEqual(env["HOME"], "/tmp")
    }

    func testSanitizedIsANoOpWhenUnset() {
        XCTAssertEqual(ToolchainEnvironment.sanitized(["PATH": "/bin"]), ["PATH": "/bin"])
    }

    // MARK: - 실제 자식이 못 본다 (러너가 정말 채택했나)

    func testProcessCommandRunnerHidesPoisonedSwiftExecFromChild() async {
        let previous = Self.setSwiftExec("/usr/bin/swift")
        defer { Self.restoreSwiftExec(previous) }
        let r = await ProcessCommandRunner().run(
            "/bin/sh", ["-c", "printf %s \"${SWIFT_EXEC-UNSET}\""], timeout: 30)
        XCTAssertEqual(r.exitCode, 0, r.stderr)
        XCTAssertEqual(r.stdout, "UNSET", "오염된 SWIFT_EXEC 가 자식에 그대로 샜다")
    }

    func testProcessCommandRunnerPassesUsableSwiftExecThrough() async {
        let previous = Self.setSwiftExec("/usr/bin/swiftc")
        defer { Self.restoreSwiftExec(previous) }
        let r = await ProcessCommandRunner().run(
            "/bin/sh", ["-c", "printf %s \"${SWIFT_EXEC-UNSET}\""], timeout: 30)
        XCTAssertEqual(r.exitCode, 0, r.stderr)
        XCTAssertEqual(r.stdout, "/usr/bin/swiftc", "멀쩡한 값까지 지웠다")
    }

    func testShellCommandHidesPoisonedSwiftExecFromChild() {
        let previous = Self.setSwiftExec("/usr/bin/swift")
        defer { Self.restoreSwiftExec(previous) }
        let r = ShellCommand.run("printf %s \"${SWIFT_EXEC-UNSET}\"", timeout: 30)
        XCTAssertEqual(r.exitCode, 0, r.stderr)
        XCTAssertEqual(r.stdout, "UNSET", "오염된 SWIFT_EXEC 가 로그인 셸 자식에 샜다")
    }

    // MARK: - 도우미 (남기면 뒤 테스트가 오염된다)

    private static func setSwiftExec(_ value: String) -> String? {
        let previous = ProcessInfo.processInfo.environment["SWIFT_EXEC"]
        setenv("SWIFT_EXEC", value, 1)
        return previous
    }

    private static func restoreSwiftExec(_ previous: String?) {
        if let previous { setenv("SWIFT_EXEC", previous, 1) } else { unsetenv("SWIFT_EXEC") }
    }
}
