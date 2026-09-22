import XCTest
@testable import CodingAgentBridgeKit

final class CodingAgentBridgeKitTests: XCTestCase {
    func testClaudeArgumentsIncludeModelAndMaxTurns() {
        let req = CodingAgentRequest(agent: "claude", prompt: "do it", model: "opus", maxTurns: 5)
        let args = CodingAgentAdapterRegistry.adapter(for: req).arguments(for: req)
        XCTAssertEqual(args.first, "claude")
        XCTAssertTrue(args.contains("-p"))
        XCTAssertTrue(args.contains("--output-format"))
        XCTAssertTrue(args.contains("--max-turns"))
        XCTAssertTrue(args.contains("opus"))
    }

    func testCodexUsesExecAndFullAuto() {
        let req = CodingAgentRequest(agent: "codex", prompt: "do it")
        let args = CodingAgentAdapterRegistry.adapter(for: req).arguments(for: req)
        XCTAssertEqual(Array(args.prefix(2)), ["codex", "exec"])
        XCTAssertTrue(args.contains("--full-auto"))
        XCTAssertFalse(args.contains("--permission-mode"))
        XCTAssertFalse(args.contains("--setting-sources"))
    }

    func testCodexBypass() {
        let req = CodingAgentRequest(agent: "codex", prompt: "p", permissionMode: "bypassPermissions")
        let args = CodingAgentAdapterRegistry.adapter(for: req).arguments(for: req)
        XCTAssertTrue(args.contains("--dangerously-bypass-approvals-and-sandbox"))
        XCTAssertFalse(args.contains("--full-auto"))
    }

    func testGrokSingleShot() {
        let req = CodingAgentRequest(agent: "grok", prompt: "ask")
        let args = CodingAgentAdapterRegistry.adapter(for: req).arguments(for: req)
        XCTAssertEqual(Array(args.prefix(3)), ["grok", "--single", "ask"])
        XCTAssertTrue(args.contains("--output-format"))
    }

    func testScriptPassesArgsVerbatim() {
        let req = CodingAgentRequest(agent: "python3", prompt: "ignored",
                                     scriptArgs: ["reaper.py", "--dry-run"])
        let args = CodingAgentAdapterRegistry.adapter(for: req).arguments(for: req)
        XCTAssertEqual(args, ["python3", "reaper.py", "--dry-run"])
    }

    func testScriptEmptyArgs() {
        let req = CodingAgentRequest(agent: "/usr/bin/true", prompt: "x",
                                     scriptArgs: [], forceScript: true)
        XCTAssertTrue(req.isScript)
        XCTAssertEqual(
            CodingAgentAdapterRegistry.adapter(for: req).arguments(for: req),
            ["/usr/bin/true"]
        )
    }

    func testSelectionByBasename() {
        let req = CodingAgentRequest(agent: "/Users/x/.grok/bin/grok", prompt: "p")
        XCTAssertTrue(CodingAgentAdapterRegistry.adapter(for: req) is GrokCodingAgentAdapter)
    }

    func testClaudeMetaParse() {
        let out = #"{"result":"done","num_turns":7,"total_cost_usd":0.42}"#
        let meta = ClaudeCodingAgentAdapter().parseMeta(out)
        XCTAssertEqual(meta.turns, 7)
        XCTAssertEqual(meta.cost, 0.42)
        XCTAssertEqual(ClaudeCodingAgentAdapter().summarize(out, killed: false), "done")
    }

    func testKindResolve() {
        XCTAssertEqual(CodingAgentKind.resolve(agentBaseName: "claude", isScript: false), .claude)
        XCTAssertEqual(CodingAgentKind.resolve(agentBaseName: "claude", isScript: true), .script)
        XCTAssertEqual(CodingAgentKind.resolve(agentBaseName: "foo", isScript: false), .generic)
    }
}
