import Testing
import Foundation
@testable import RoomKit

/// `LaunchArgvBuilder`(agent-work-todo) 삭제 후 골든 테스트.
/// 동일 입력 → 동일 argv 를 보장한다 (설계도 §7 검증).
@Suite struct LaunchArgvTests {
    @Test func parseToolFromOccupant() {
        #expect(LaunchArgv.parseTool(from: "agent:claude@macbook") == .claude)
        #expect(LaunchArgv.parseTool(from: "agent:agy@macbook") == .agy)
        #expect(LaunchArgv.parseTool(from: "agent:grok@macbook") == .grok)
        #expect(LaunchArgv.parseTool(from: "agent:codex@macbook") == .codex)
        #expect(LaunchArgv.parseTool(from: "not-agent") == nil)
    }

    @Test func buildExecArgvForClaude() {
        let argv = LaunchArgv.buildExecArgv(
            tool: .claude, promptFile: "/tmp/prompt.md", promptText: "PROMPT BODY",
            model: nil, workdir: nil)
        #expect(argv == [
            "claude", "-p", "PROMPT BODY",
            "--dangerously-skip-permissions",
            "--output-format", "text"
        ])
    }

    @Test func buildExecArgvForClaudeWithModel() {
        let argv = LaunchArgv.buildExecArgv(
            tool: .claude, promptFile: "/tmp/prompt.md", promptText: "PROMPT BODY",
            model: "claude-fable-5-1", workdir: nil)
        #expect(argv == [
            "claude", "-p", "PROMPT BODY",
            "--dangerously-skip-permissions",
            "--output-format", "text",
            "--model", "claude-fable-5-1"
        ])
    }

    @Test func buildExecArgvForAgy() {
        let argv = LaunchArgv.buildExecArgv(
            tool: .agy, promptFile: "/tmp/prompt.md", promptText: "PROMPT BODY",
            model: "o3-pro", workdir: nil)
        #expect(argv == [
            "agy", "-p", "PROMPT BODY",
            "--model", "o3-pro",
            "--dangerously-skip-permissions",
            "--input-format", "text",
            "--output-format", "stream-json",
            "--print-timeout", LaunchArgv.defaultAgyPrintTimeout
        ])
    }

    @Test func buildExecArgvForAgyWithoutModelReturnsEmpty() {
        let argv = LaunchArgv.buildExecArgv(
            tool: .agy, promptFile: "/tmp/prompt.md", promptText: "PROMPT BODY",
            model: nil, workdir: nil)
        #expect(argv.isEmpty)
    }

    @Test func buildExecArgvForAgyWithoutPromptTextReturnsEmpty() {
        let argv = LaunchArgv.buildExecArgv(
            tool: .agy, promptFile: "/tmp/prompt.md", promptText: "",
            model: "o3-pro", workdir: nil)
        #expect(argv.isEmpty)
    }

    @Test func buildExecArgvForGrok() {
        let argv = LaunchArgv.buildExecArgv(
            tool: .grok, promptFile: "/tmp/prompt.md", promptText: "PROMPT BODY",
            model: nil, workdir: "/work/dir")
        #expect(argv == [
            "grok", "--cwd", "/work/dir",
            "--always-approve",
            "--output-format", "streaming-messages-json",
            "--max-turns", "200",
            "--prompt-file", "/tmp/prompt.md"
        ])
    }

    @Test func buildExecArgvForGrokWithoutWorkdir() {
        let argv = LaunchArgv.buildExecArgv(
            tool: .grok, promptFile: "/tmp/prompt.md", promptText: "PROMPT BODY",
            model: nil, workdir: nil)
        #expect(argv == [
            "grok",
            "--always-approve",
            "--output-format", "streaming-messages-json",
            "--max-turns", "200",
            "--prompt-file", "/tmp/prompt.md"
        ])
    }

    @Test func buildExecArgvForGrokInlinePromptUsesSingleTurn() {
        let argv = LaunchArgv.buildExecArgv(
            tool: .grok, promptFile: "", promptText: "PROMPT BODY",
            model: nil, workdir: "/work/dir")
        #expect(argv == [
            "grok", "--cwd", "/work/dir",
            "--always-approve",
            "--output-format", "streaming-messages-json",
            "--max-turns", "200",
            "-p", "PROMPT BODY"
        ])
    }

    @Test func buildExecArgvForGrokWithoutPromptReturnsEmpty() {
        let argv = LaunchArgv.buildExecArgv(
            tool: .grok, promptFile: "", promptText: "",
            model: nil, workdir: "/work/dir")
        #expect(argv.isEmpty)
    }

    @Test func buildExecArgvForCursor() {
        let argv = LaunchArgv.buildExecArgv(
            tool: .cursor, promptFile: "/tmp/prompt.md", promptText: "PROMPT BODY",
            model: "claude-4.5-sonnet", workdir: nil)
        #expect(argv == [
            "cursor-agent",
            "-p", "PROMPT BODY",
            "--output-format", "stream-json",
            "-f",
            "--model", "claude-4.5-sonnet"
        ])
    }

    @Test func buildExecArgvForCursorWithoutPromptReturnsEmpty() {
        let argv = LaunchArgv.buildExecArgv(
            tool: .cursor, promptFile: "/tmp/prompt.md", promptText: "",
            model: "claude-4.5-sonnet", workdir: nil)
        #expect(argv.isEmpty)
    }

    @Test func buildOpenArgvBasic() {
        let id = UUID()
        let argv = LaunchArgv.buildOpenArgv(roomID: id, tool: .claude)
        #expect(argv == [
            "agent-room-terminal", "open", id.uuidString,
            "--tool", "claude", "--execute"
        ])
    }

    @Test func buildOpenArgvWithOpenPreset() {
        let id = UUID()
        let argv = LaunchArgv.buildOpenArgv(roomID: id, tool: .agy, preset: .open)
        #expect(argv == [
            "agent-room-terminal", "open", id.uuidString,
            "--tool", "agy", "--execute", "--preset", "open"
        ])
    }

    @Test func buildOpenArgvWithJSON() {
        let id = UUID()
        let argv = LaunchArgv.buildOpenArgv(
            roomID: id, specURL: nil, tool: .claude, preset: nil, json: true)
        #expect(argv == [
            "agent-room-terminal", "open", id.uuidString,
            "--tool", "claude", "--execute", "--json"
        ])
    }

    @Test func buildOpenArgvWithSpecURL() {
        let specURL = URL(fileURLWithPath: "/path/to/spec.json")
        let argv = LaunchArgv.buildOpenArgv(
            specURL: specURL,
            tool: .claude,
            preset: .toolbelt,
            json: true
        )
        #expect(argv == [
            "agent-room-terminal", "open", "--spec", "/path/to/spec.json",
            "--tool", "claude", "--execute", "--preset", "toolbelt", "--json"
        ])
    }

    @Test func displayCommandCollapsesPromptBody() {
        let argv = LaunchArgv.buildExecArgv(
            tool: .claude, promptFile: "/tmp/prompt.md", promptText: "PROMPT BODY",
            model: nil, workdir: nil)
        let shown = LaunchArgv.displayCommand(
            argv: argv, promptText: "PROMPT BODY", promptFile: "/tmp/prompt.md")
        #expect(shown.contains("@/tmp/prompt.md"))
        #expect(!shown.contains("PROMPT BODY"))
    }

    @Test func parseOpenPathSuccessful() {
        let jsonStr = "{\"ok\":true,\"result\":{\"path\":\"/tmp/room-test-123\"}}"
        let (path, note) = LaunchArgv.parseOpenPath(from: jsonStr.data(using: .utf8)!)
        #expect(path == "/tmp/room-test-123")
        #expect(note == nil)
    }

    @Test func parseOpenPathFailureWithError() {
        let jsonStr = "{\"ok\":false,\"error\":\"room terminal daemon not running\"}"
        let (path, note) = LaunchArgv.parseOpenPath(from: jsonStr.data(using: .utf8)!)
        #expect(path == nil)
        #expect(note == "agent-room-terminal open 실패: room terminal daemon not running")
    }

    @Test func parseOpenPathMalformedData() {
        let malformed = "not json at all"
        let (path, note) = LaunchArgv.parseOpenPath(from: malformed.data(using: .utf8)!)
        #expect(path == nil)
        #expect(note == "open 출력 파싱 실패: 유효한 JSON이 아님")
    }
}
