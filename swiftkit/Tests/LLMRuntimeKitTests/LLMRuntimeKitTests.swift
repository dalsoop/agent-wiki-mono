import XCTest
@testable import LLMRuntimeKit
import AgentRegistryKit

final class LLMRuntimeKitTests: XCTestCase {

    // MARK: - ClaudeResultParser (결정적 — 실제 프로세스 없음)

    func testClaudeParserValidJSON() {
        let json = #"{"result":"hello","session_id":"s1","is_error":false,"num_turns":2,"total_cost_usd":0.01}"#
        let r = ClaudeResultParser.parse(stdout: json, exitCode: 0, stderr: "")
        XCTAssertEqual(r.text, "hello")
        XCTAssertEqual(r.sessionID, "s1")
        XCTAssertFalse(r.isError)
        XCTAssertEqual(r.numTurns, 2)
        XCTAssertEqual(r.costUSD, 0.01)
    }

    func testClaudeParserErrorResult() {
        let json = #"{"result":"boom","is_error":true}"#
        let r = ClaudeResultParser.parse(stdout: json, exitCode: 0, stderr: "")
        XCTAssertTrue(r.isError)
        XCTAssertEqual(r.text, "boom")
    }

    func testClaudeParserNonJSONFallback() {
        let r = ClaudeResultParser.parse(stdout: "plain text answer", exitCode: 0, stderr: "")
        XCTAssertEqual(r.text, "plain text answer")
        XCTAssertFalse(r.isError)
    }

    func testClaudeParserNonZeroExitWithoutJSONUsesStderr() {
        let r = ClaudeResultParser.parse(stdout: "", exitCode: 1, stderr: "auth failed")
        XCTAssertTrue(r.isError)
        XCTAssertEqual(r.text, "auth failed")
    }

    // MARK: - dispatch (AgentDef.agent -> backend)

    func testDispatchClaude() {
        let rt = LLMRuntime()
        XCTAssertTrue(rt.backend(for: AgentDef(identity: .init(name: "n"), runtime: .init(agent: "claude"))) is ClaudeCodeBackend)
    }

    func testDispatchCodex() {
        let rt = LLMRuntime()
        XCTAssertTrue(rt.backend(for: AgentDef(identity: .init(name: "n"), runtime: .init(agent: "codex"))) is CodexBackend)
    }

    func testDispatchGrok() {
        let rt = LLMRuntime()
        XCTAssertTrue(rt.backend(for: AgentDef(identity: .init(name: "n"), runtime: .init(agent: "grok"))) is GrokBackend)
    }

    func testDispatchUnknownDefaultsClaude() {
        let rt = LLMRuntime()
        XCTAssertTrue(rt.backend(for: AgentDef(identity: .init(name: "n"), runtime: .init(agent: "unknown-llm"))) is ClaudeCodeBackend)
    }

    // MARK: - Grok headless backend

    func testGrokRunUsesHeadlessSinglePromptArguments() async throws {
        let backend = GrokBackend(executableOverride: "/bin/echo")
        let result = try await backend.run(LLMRunRequest(
            prompt: "hello grok",
            agent: AgentDef(identity: .init(name: "n"), runtime: .init(agent: "grok")),
            maxTurns: 3))
        XCTAssertTrue(result.text.contains("--single hello grok"))
        XCTAssertTrue(result.text.contains("--output-format plain"))
        XCTAssertTrue(result.text.contains("--no-alt-screen"))
        XCTAssertTrue(result.text.contains("--max-turns 3"))
        XCTAssertFalse(result.isError)
    }

    // MARK: - composedPrompt (컨텍스트 머리 병합)

    func testComposedPromptWithContextPreamble() {
        let req = LLMRunRequest(prompt: "list tables",
                                agent: AgentDef(identity: .init(name: "n")),
                                contextPreamble: "DB: sqlite://test.db")
        XCTAssertEqual(req.composedPrompt, "DB: sqlite://test.db\n\nlist tables")
    }

    func testComposedPromptWithoutPreamble() {
        let req = LLMRunRequest(prompt: "list tables", agent: AgentDef(identity: .init(name: "n")))
        XCTAssertEqual(req.composedPrompt, "list tables")
    }

    func testComposedPromptEmptyPreambleIgnored() {
        let req = LLMRunRequest(prompt: "list tables", agent: AgentDef(identity: .init(name: "n")), contextPreamble: "")
        XCTAssertEqual(req.composedPrompt, "list tables")
    }

    // MARK: - shellQuote

    func testShellQuoteEscapesSingleQuote() {
        XCTAssertEqual(shellQuote("a'b"), #"'a'\''b'"#)
    }
}
