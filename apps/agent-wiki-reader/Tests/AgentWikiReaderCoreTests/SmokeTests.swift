import AppScaffoldKit
import XCTest
import CommandKit
@testable import AgentWikiReaderCore

final class SmokeTests: XCTestCase {
    func testAppFormContractCompliance() {
        XCTAssertTrue(RanodeAppFormContract.assertConforms(slug: "agent-wiki-reader"))
    }

    func testBlocksPublish() {
        XCTAssertFalse(AgentWikiReaderService.isReadOnlyInvocation(["publish"]))
        XCTAssertFalse(AgentWikiReaderService.isReadOnlyInvocation(["capture", "http://x"]))
        XCTAssertFalse(AgentWikiReaderService.isReadOnlyInvocation(["promotion", "preview", "x"]))
    }

    func testAllowsShowSearch() {
        XCTAssertTrue(AgentWikiReaderService.isReadOnlyInvocation(["show", "온보딩"]))
        XCTAssertTrue(AgentWikiReaderService.isReadOnlyInvocation(["--world", "person-personal", "list"]))
        XCTAssertTrue(AgentWikiReaderService.isReadOnlyInvocation(["gujo", "status"]))
        XCTAssertFalse(AgentWikiReaderService.isReadOnlyInvocation(["gujo", "sync"]))
        XCTAssertTrue(AgentWikiReaderService.isReadOnlyInvocation(["search", "온보딩"]))
    }

    func testAllowsReaderAreas() {
        XCTAssertTrue(AgentWikiReaderService.isReadOnlyInvocation(["recent"]))
        XCTAssertTrue(AgentWikiReaderService.isReadOnlyInvocation(["recent", "20"]))
        XCTAssertTrue(AgentWikiReaderService.isReadOnlyInvocation(["discuss"]))
        XCTAssertTrue(AgentWikiReaderService.isReadOnlyInvocation(["structure", "--json"]))
        XCTAssertTrue(AgentWikiReaderService.isReadOnlyInvocation(["graph", "status"]))
        XCTAssertTrue(AgentWikiReaderService.isReadOnlyInvocation(["graph", "timeline", "abc"]))
        XCTAssertFalse(AgentWikiReaderService.isReadOnlyInvocation(["graph", "rebuild"]))
        XCTAssertTrue(AgentWikiReaderService.isReadOnlyInvocation(["event", "tail"]))
        XCTAssertTrue(AgentWikiReaderService.isReadOnlyInvocation(["event", "tree"]))
        XCTAssertFalse(AgentWikiReaderService.isReadOnlyInvocation(["event", "append"]))
        XCTAssertFalse(AgentWikiReaderService.isReadOnlyInvocation(["event", "start"]))
        XCTAssertTrue(AgentWikiReaderService.isReadOnlyInvocation(["blob", "get", "abc"]))
        XCTAssertTrue(AgentWikiReaderService.isReadOnlyInvocation(["blob", "list"]))
        XCTAssertFalse(AgentWikiReaderService.isReadOnlyInvocation(["blob", "put", "file"]))
    }

    func testForwardBlocksWithoutRunning() async {
        struct Mock: CommandRunning {
            func run(_ launchPath: String, _ arguments: [String], timeout: TimeInterval?) async -> CommandResult {
                XCTFail("should not run agent-wiki for publish")
                return CommandResult(stdout: "", stderr: "", exitCode: 1)
            }
        }
        let svc = AgentWikiReaderService(runner: Mock())
        let r = await svc.forward(args: ["publish", "--title", "x"])
        XCTAssertEqual(r.exitCode, 64)
        XCTAssertTrue(r.stderr.contains("blocked"))
    }

    func testStatusCallsWorldList() async {
        struct Mock: CommandRunning {
            func run(_ launchPath: String, _ arguments: [String], timeout: TimeInterval?) async -> CommandResult {
                XCTAssertTrue(arguments.contains("world") || arguments.first == "world")
                return CommandResult(stdout: "person-personal\n", stderr: "", exitCode: 0)
            }
        }
        let s = await AgentWikiReaderService(runner: Mock()).status()
        XCTAssertTrue(s.contains("person-personal"))
    }
}
