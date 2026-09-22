import Foundation
import XCTest
@testable import ClaudeRuntimeKit

final class ClaudeRuntimeKitTests: XCTestCase {
    func testParsesLoggedInClaudeStatus() throws {
        let data = try XCTUnwrap("""
        {"loggedIn":true,"orgId":"org-team","email":"team@example.com"}
        """.data(using: .utf8))

        XCTAssertEqual(
            ClaudeAuthStatus.parse(json: data),
            ClaudeAuthStatus(loggedIn: true, organizationID: "org-team", email: "team@example.com")
        )
    }

    func testRejectsMalformedOrMissingLoginStatus() {
        XCTAssertNil(ClaudeAuthStatus.parse(json: Data("{}".utf8)))
        XCTAssertNil(ClaudeAuthStatus.parse(json: Data("not-json".utf8)))
    }

    func testZaiEnvironmentUsesDefaultsAndOverrides() {
        let environment = ClaudeZaiRuntime.environment(
            token: "token",
            baseURL: "https://proxy.example",
            sonnetModel: "sonnet-custom",
            haikuModel: "haiku-custom"
        )

        XCTAssertEqual(Set(environment.keys), ClaudeZaiRuntime.environmentKeys)
        XCTAssertEqual(environment["ANTHROPIC_BASE_URL"], "https://proxy.example")
        XCTAssertEqual(environment["ANTHROPIC_DEFAULT_SONNET_MODEL"], "sonnet-custom")
        XCTAssertEqual(environment["ANTHROPIC_DEFAULT_OPUS_MODEL"], ClaudeZaiRuntime.opusModel)
        XCTAssertEqual(environment["ANTHROPIC_DEFAULT_HAIKU_MODEL"], "haiku-custom")
    }

    func testCommandRunnerCapturesOutputAndExitStatus() {
        let result = ClaudeCommandRunner.run(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "printf RUNTIME_OK"],
            timeout: 1
        )
        XCTAssertEqual(result?.terminationStatus, 0)
        XCTAssertEqual(result?.output, "RUNTIME_OK")
        XCTAssertEqual(result?.timedOut, false)
    }

    func testCommandRunnerWaitsForForcedTerminationBeforeReadingStatus() {
        let startedAt = Date()
        let result = ClaudeCommandRunner.run(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "trap '' TERM; while :; do sleep 1; done"],
            timeout: 0.05
        )

        XCTAssertEqual(result?.timedOut, true)
        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 3)
    }

    func testClaudeStatusEnvironmentPrependsInstalledHomebrewDirectory() {
        let fm = FakeFileManager(executablePaths: ["/opt/homebrew/bin/claude"])
        let environment = ClaudeAuthStatusReader.environmentForClaudeCLI(
            base: ["PATH": "/usr/bin:/bin"],
            preferredDirectories: ["/opt/homebrew/bin"],
            fileManager: fm
        )

        XCTAssertEqual(environment["PATH"], "/opt/homebrew/bin:/usr/bin:/bin")
    }

    func testClaudeStatusEnvironmentDoesNotDuplicateExistingDirectory() {
        let fm = FakeFileManager(executablePaths: ["/opt/homebrew/bin/claude"])
        let environment = ClaudeAuthStatusReader.environmentForClaudeCLI(
            base: ["PATH": "/opt/homebrew/bin:/usr/bin"],
            preferredDirectories: ["/opt/homebrew/bin"],
            fileManager: fm
        )

        XCTAssertEqual(environment["PATH"], "/opt/homebrew/bin:/usr/bin")
    }

    func testClaudeStatusDirectoriesIncludeClaudeUpdaterLocationBeforeHomebrew() {
        XCTAssertEqual(
            ClaudeAuthStatusReader.preferredClaudeDirectories(homeDirectory: "/Users/test"),
            ["/Users/test/.local/bin", "/opt/homebrew/bin", "/usr/local/bin"]
        )
    }

    func testClaudeStatusEnvironmentRestoresUserForKeychainLookup() {
        let fm = FakeFileManager(executablePaths: ["/Users/test/.local/bin/claude"])
        let environment = ClaudeAuthStatusReader.environmentForClaudeCLI(
            base: ["HOME": "/Users/test", "PATH": "/usr/bin:/bin"],
            preferredDirectories: ["/Users/test/.local/bin"],
            currentUsername: "test",
            fileManager: fm
        )

        XCTAssertEqual(environment["USER"], "test")
        XCTAssertEqual(environment["PATH"], "/Users/test/.local/bin:/usr/bin:/bin")
    }

    func testClaudeStatusEnvironmentPreservesExplicitUser() {
        let environment = ClaudeAuthStatusReader.environmentForClaudeCLI(
            base: ["PATH": "/usr/bin:/bin", "USER": "explicit"],
            preferredDirectories: [],
            currentUsername: "fallback",
            fileManager: FakeFileManager(executablePaths: [])
        )

        XCTAssertEqual(environment["USER"], "explicit")
    }
}

private final class FakeFileManager: FileManager, @unchecked Sendable {
    private let executablePaths: Set<String>

    init(executablePaths: Set<String>) {
        self.executablePaths = executablePaths
        super.init()
    }

    override func isExecutableFile(atPath path: String) -> Bool {
        executablePaths.contains(path)
    }
}
