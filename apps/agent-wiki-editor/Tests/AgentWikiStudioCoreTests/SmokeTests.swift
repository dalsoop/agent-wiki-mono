import AppScaffoldKit
import XCTest
import CommandKit
@testable import AgentWikiStudioCore

final class SmokeTests: XCTestCase {
    func testAppFormContractCompliance() {
        XCTAssertTrue(RanodeAppFormContract.assertConforms(slug: "agent-wiki-studio"))
    }

    func testForwardPublishRunsAgentWiki() async {
        struct Mock: CommandRunning {
            func run(_ launchPath: String, _ arguments: [String], timeout: TimeInterval?) async -> CommandResult {
                XCTAssertTrue(launchPath.contains("agent-wiki"))
                XCTAssertEqual(arguments.first, "publish")
                return CommandResult(stdout: "ok-id\n", stderr: "", exitCode: 0)
            }
        }
        let r = await AgentWikiStudioService(runner: Mock()).forward(args: ["publish", "--title", "t"])
        XCTAssertEqual(r.exitCode, 0)
        XCTAssertTrue(r.stdout.contains("ok-id"))
    }

    func testRunWithStdinPipesBodyToChildProcess() async {
        let r = await AgentWikiStudioService.runWithStdin("/bin/cat", [], stdin: "hello studio")
        XCTAssertEqual(r.exitCode, 0)
        XCTAssertEqual(r.stdout, "hello studio")
        XCTAssertEqual(r.stderr, "")
    }

    func testListRecordsDecodesJSONEnvelope() async {
        struct Mock: CommandRunning {
            func run(_ launchPath: String, _ arguments: [String], timeout: TimeInterval?) async -> CommandResult {
                XCTAssertEqual(arguments, ["--world", "gujo-wiki", "list", "--json"])
                let json = """
                {"ok":true,"result":{"objects":[{"id":"abc123","title":"제목","author":"a@h","published":"2026-08-06","batch":null}],"note":"1 objects"}}
                """
                return CommandResult(stdout: json, stderr: "", exitCode: 0)
            }
        }
        let r = await AgentWikiStudioService(runner: Mock()).listRecords(world: "gujo-wiki")
        XCTAssertNil(r.error)
        XCTAssertEqual(r.records.count, 1)
        XCTAssertEqual(r.records.first?.id, "abc123")
        XCTAssertEqual(r.records.first?.title, "제목")
    }

    func testInferredWriteWorldUsesTenantSlugNotGujo() {
        XCTAssertEqual(
            StudioWriteWorld.inferred(tenantID: "tenant:family", contextURL: URL(fileURLWithPath: "/no-such.json")),
            "person-family"
        )
        XCTAssertEqual(
            StudioWriteWorld.inferred(tenantID: nil, contextURL: URL(fileURLWithPath: "/no-such.json")),
            "person-personal"
        )
        XCTAssertEqual(StudioWriteWorld.slug(fromTenantID: "tenant:silneobal"), "silneobal")
    }
}
