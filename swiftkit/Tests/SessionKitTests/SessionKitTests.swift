import XCTest
@testable import SessionKit

final class SessionIdentTests: XCTestCase {
    func testProjectNameWorktreeConvention() {
        XCTAssertEqual(SessionIdent.projectName(cwd: "/Users/j/WORK/swift-app-mono/main"), "swift-app-mono/main")
        // trailing wt-*/feat-* segment is prefixed with its immediate parent dir
        XCTAssertEqual(SessionIdent.projectName(cwd: "/Users/j/WORK/swift-app-mono/.worktrees/wt-foo"), ".worktrees/wt-foo")
        XCTAssertEqual(SessionIdent.projectName(cwd: "/Users/j/laravel-mono"), "laravel-mono")
        XCTAssertEqual(SessionIdent.projectName(cwd: "/a/b/feat-x"), "b/feat-x")
    }
    func testMCPServer() {
        XCTAssertEqual(SessionIdent.mcpServer(fromToolName: "mcp__excel__read_data"), "excel")
        XCTAssertNil(SessionIdent.mcpServer(fromToolName: "Bash"))
    }
    func testCodexUUID() {
        XCTAssertEqual(SessionIdent.codexUUID(fromFileName: "rollout-2026-07-19T10-00-00-1a2b3c4d-5e6f-7a8b-9c0d-1e2f3a4b5c6d.jsonl"),
                       "1a2b3c4d-5e6f-7a8b-9c0d-1e2f3a4b5c6d")
        XCTAssertNil(SessionIdent.codexUUID(fromFileName: "notes.jsonl"))
    }
    func testCommandHead() {
        XCTAssertEqual(SessionIdent.commandHead("/bin/ls -la /tmp"), "ls")
        XCTAssertEqual(SessionIdent.commandHead("git commit -m x"), "git")
    }
    func testFlexibleISO() {
        XCTAssertNotNil(SessionTime.parse("2026-07-19T10:00:00.123Z"))
        XCTAssertNotNil(SessionTime.parse("2026-07-19T10:00:00Z"))
        XCTAssertNil(SessionTime.parse("not-a-date"))
        XCTAssertNil(SessionTime.parse(nil))
        XCTAssertEqual(SessionTime.parseUnix(1_700_000_000)?.timeIntervalSince1970, 1_700_000_000)
    }
}

final class SessionMetaTests: XCTestCase {
    func testClaudeHead() {
        let head = """
        {"type":"summary"}
        {"cwd":"/Users/j/proj/main","type":"file-history-snapshot"}
        {"type":"user","message":{"content":"first real prompt"}}
        {"type":"assistant","message":{"content":"reply"}}
        """
        let m = SessionMeta.claude(head: head)
        XCTAssertEqual(m.cwd, "/Users/j/proj/main")
        XCTAssertEqual(m.firstPrompt, "first real prompt")
    }
    func testClaudeHeadSkipsNoise() {
        let head = """
        {"cwd":"/x","type":"user","message":{"content":"Caveat: this is injected"}}
        {"type":"user","message":{"content":"actual question"}}
        """
        XCTAssertEqual(SessionMeta.claude(head: head).firstPrompt, "actual question")
    }
    func testClaudeContentBlocks() {
        let head = #"{"type":"user","message":{"content":[{"type":"text","text":"blocky prompt"}]}}"#
        XCTAssertEqual(SessionMeta.claude(head: head).firstPrompt, "blocky prompt")
    }
    func testCodexMeta() {
        let head = #"{"type":"session_meta","payload":{"cwd":"/w","id":"abc","parent_thread_id":"p1","agent_nickname":"scout"}}"#
        let m = SessionMeta.codex(head: head)
        XCTAssertEqual(m.cwd, "/w"); XCTAssertEqual(m.id, "abc")
        XCTAssertEqual(m.parentThreadID, "p1"); XCTAssertEqual(m.nickname, "scout")
    }
    func testCodexIndex() {
        let text = """
        {"id":"a","thread_name":"Alpha"}
        {"id":"b","thread_name":"Beta"}
        {"id":"c"}
        """
        let map = SessionMeta.codexIndex(text: text)
        XCTAssertEqual(map, ["a": "Alpha", "b": "Beta"])
    }
    func testGrokSummaryAndPrompt() {
        let summary = #"{"info":{"id":"g1","cwd":"/work/grok"},"generated_title":"Grok title","# +
            #""session_summary":"Fallback","current_model_id":"grok-4.5","# +
            #""created_at":"2026-07-27T01:00:00Z","last_active_at":"2026-07-27T02:00:00Z","agent_name":"build"}"#

        let meta = SessionMeta.grok(summary: summary)
        XCTAssertEqual(meta?.id, "g1")
        XCTAssertEqual(meta?.cwd, "/work/grok")
        XCTAssertEqual(meta?.title, "Grok title")
        XCTAssertEqual(meta?.modelID, "grok-4.5")

        let updates = #"{"timestamp":1784902994,"method":"session/update","# +
            #""params":{"sessionId":"g1","update":{"sessionUpdate":"user_message_chunk","# +
            #""content":{"type":"text","text":"Grok 질문"}}}}"#
        XCTAssertEqual(SessionMeta.grokFirstPrompt(head: updates), "Grok 질문")
    }
}

final class SessionLineTests: XCTestCase {
    func testDecodeAndCodexPayload() {
        let obj = SessionLine.decode(#"{"response_item":{"payload":{"type":"message"}}}"#)
        XCTAssertNotNil(obj)
        XCTAssertEqual(SessionLine.codexPayload(obj!)?["type"] as? String, "message")
    }
    func testLinesFilterEmpty() {
        XCTAssertEqual(SessionHead.lines("a\n\nb\n").count, 2)
    }
    func testGrokUpdate() {
        let obj = SessionLine.decode(#"{"method":"_x.ai/session/update","params":{"update":{"sessionUpdate":"tool_call","title":"read_file"}}}"#)
        XCTAssertEqual(SessionLine.grokUpdate(obj!)?["title"] as? String, "read_file")
    }
}

final class AIRuntimeTests: XCTestCase {
    func testRuntimeCatalog() {
        XCTAssertEqual(AIRuntime.allCases, [.claude, .codex, .grok, .agy, .opencode, .cursor])
        XCTAssertEqual(SupportedAIAgentCLI.allCases, [.claude, .codex, .grok, .agy, .opencode, .cursor])
        XCTAssertEqual(AIRuntime.grok.displayName, "Grok")
        XCTAssertEqual(AIRuntime.grok.resumeArguments(sessionID: "g1"), ["--resume", "g1"])
        // Antigravity: 실행 파일은 agy, 데이터는 Gemini 계열 경로, 재개는 --conversation.
        XCTAssertEqual(AIRuntime.agy.displayName, "Antigravity")
        XCTAssertEqual(AIRuntime.agy.executableName, "agy")
        XCTAssertEqual(AIRuntime.agy.executable, "agy")
        XCTAssertEqual(AIRuntime.agy.defaultStateDirectoryName, ".gemini/antigravity-cli")
        XCTAssertEqual(AIRuntime.agy.resumeArguments(sessionID: "a1"), ["--conversation", "a1"])
        // OpenCode 및 Cursor 인터페이스 검증
        XCTAssertEqual(SupportedAIAgentCLI.opencode.displayName, "OpenCode")
        XCTAssertEqual(SupportedAIAgentCLI.opencode.executableName, "opencode")
        XCTAssertEqual(SupportedAIAgentCLI.cursor.displayName, "Cursor")
        XCTAssertEqual(SupportedAIAgentCLI.cursor.executableName, "cursor-agent")
    }

    func testSupportedAIAgentCLITypealiasEquivalence() {
        let cli: SupportedAIAgentCLI = .claude
        let runtime: AIRuntime = cli
        XCTAssertEqual(cli, runtime)
    }
}
