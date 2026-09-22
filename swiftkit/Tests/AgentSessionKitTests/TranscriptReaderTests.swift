import XCTest
@testable import AgentSessionKit

/// 이 저장소에만 같은 파서가 셋이었고, 따라서 **버그도 셋이었다**.
/// 여기가 이제 그 지식의 유일한 자리다 — 툴별 어휘를 실제 줄 모양으로 못박는다.
final class TranscriptReaderTests: XCTestCase {
    func testClaudeRolesAndTools() {
        let text = [
            #"{"type":"user","message":{"content":"로그인 고쳐줘"}}"#,
            #"{"type":"assistant","message":{"content":[{"type":"thinking","thinking":"음"},{"type":"text","text":"고쳤습니다"},{"type":"tool_use","name":"Edit","input":{"file_path":"/a/b.swift"}}]}}"#,
            #"{"type":"user","message":{"content":[{"type":"tool_result","content":"ok"}]}}"#,
        ].joined(separator: "\n")
        let r = TranscriptReader.turns(text: text, tool: .claude)
        XCTAssertEqual(r.turns.map(\.role), [.user, .thinking, .assistant, .tool, .toolResult])
        XCTAssertEqual(r.turns[0].text, "로그인 고쳐줘")
        XCTAssertEqual(r.turns[3].toolName, "Edit")
        XCTAssertTrue(r.turns[3].text.contains("/a/b.swift"), "무슨 파일을 건드렸는지가 핵심이다")
        XCTAssertTrue(r.turns[4].text.hasPrefix("↳"))
    }

    func testCodexEnvelopesBothShapes() {
        let text = [
            #"{"type":"event_msg","payload":{"type":"user_message","message":"이거 해줘"}}"#,
            #"{"type":"event_msg","payload":{"type":"agent_message","message":"했습니다"}}"#,
            #"{"type":"event_msg","payload":{"type":"exec_command_end","command":["/bin/zsh","-lc","swift test"]}}"#,
            #"{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"또 있어"}]}}"#,
        ].joined(separator: "\n")
        let r = TranscriptReader.turns(text: text, tool: .codex)
        XCTAssertEqual(r.turns.map(\.role), [.user, .assistant, .tool, .user])
        XCTAssertEqual(r.turns[2].text, "swift test", "셸 래퍼를 벗겨야 읽힌다")
    }

    func testGrokACPStream() {
        let text = [
            #"{"params":{"update":{"sessionUpdate":"user_message_chunk","content":{"type":"text","text":"확인해줘"}}}}"#,
            #"{"params":{"update":{"sessionUpdate":"agent_thought_chunk","content":{"type":"text","text":"생각"}}}}"#,
            #"{"params":{"update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"됐습니다"}}}}"#,
        ].joined(separator: "\n")
        let r = TranscriptReader.turns(text: text, tool: .grok)
        XCTAssertEqual(r.turns.map(\.role), [.user, .thinking, .assistant])
    }

    /// 셋이 각자 갖고 있던 버그 — 이미지가 붙은 사용자 지시를 통째로 버렸다.
    func testOversizedLineKeepsHumanText() {
        let blob = String(repeating: "A", count: 700_000)
        let text = #"{"type":"event_msg","payload":{"type":"user_message","message":"이거 고쳐줘","images":["\#(blob)"]}}"#
        let r = TranscriptReader.turns(text: text, tool: .codex)
        XCTAssertEqual(r.turns.first?.text, "이거 고쳐줘")
        XCTAssertFalse(r.turns.contains { $0.text.contains("AAAA") })
    }

    /// 뷰마다 필요한 게 다르다 — 사고 과정·툴을 끌 수 있어야 한 파서를 같이 쓴다.
    func testOptionsFilterKinds() {
        let text = [
            #"{"type":"user","message":{"content":"해줘"}}"#,
            #"{"type":"assistant","message":{"content":[{"type":"thinking","thinking":"음"},{"type":"tool_use","name":"Bash","input":{"command":"ls"}}]}}"#,
        ].joined(separator: "\n")
        let bare = TranscriptReader.turns(text: text, tool: .claude,
                                          options: .init(includeThinking: false, includeTools: false))
        XCTAssertEqual(bare.turns.map(\.role), [.user])
    }

    func testMaxTurnsMarksTruncated() {
        let text = (1...20).map { #"{"type":"user","message":{"content":"\#($0)"}}"# }.joined(separator: "\n")
        let r = TranscriptReader.turns(text: text, tool: .claude, options: .init(maxTurns: 5))
        XCTAssertEqual(r.turns.count, 5)
        XCTAssertTrue(r.truncated)
    }

    /// grok 은 세션이 디렉터리다 — 파일에서 바로 읽는 경로가 그걸 알아야 한다.
    func testReadFromGrokDirectory() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tr-\(UUID().uuidString)/019f-s")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }
        try #"{"params":{"update":{"sessionUpdate":"user_message_chunk","content":{"type":"text","text":"안녕"}}}}"#
            .write(to: dir.appendingPathComponent("updates.jsonl"), atomically: true, encoding: .utf8)
        let ref = SessionRef(tool: .grok, id: "019f-s", cwd: "/ws", title: nil,
                             lastActive: Date(), path: dir.path, messageCount: 1)
        XCTAssertEqual(TranscriptReader.read(ref).turns.first?.text, "안녕")
    }
}
