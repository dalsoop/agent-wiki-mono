import XCTest
@testable import AgentSessionKit

/// 서브에이전트 결과는 툴 리턴이 아니라 나중에 오는 알림으로 돌아온다.
/// 그 알림이 `<` 로 시작한다는 이유로 버려지면 "시킨 것"만 남고 "된 것"이 사라진다.
final class TaskNoticeTests: XCTestCase {
    private let block = """
    <task-notification>
    <task-id>bkgxr69vu</task-id>
    <tool-use-id>toolu_01SqmFhVSpuKNfXcW9dMJggt</tool-use-id>
    <output-file>/tmp/tasks/bkgxr69vu.output</output-file>
    <status>completed</status>
    <summary>Background command "Wait for CI" completed (exit code 0)</summary>
    </task-notification>
    """

    func testParsesEveryField() throws {
        let n = try XCTUnwrap(TaskNotice.parse(block))
        XCTAssertEqual(n.taskId, "bkgxr69vu")
        XCTAssertEqual(n.toolUseId, "toolu_01SqmFhVSpuKNfXcW9dMJggt")
        XCTAssertEqual(n.outputFile, "/tmp/tasks/bkgxr69vu.output")
        XCTAssertTrue(n.succeeded)
        XCTAssertEqual(n.summary?.contains("Wait for CI"), true)
    }

    func testPlainTextIsNotNotice() {
        XCTAssertNil(TaskNotice.parse("이거 머지하고 진행해봐"))
    }

    /// 예전엔 이 줄이 통째로 사라져 전사본에 결과가 없었다.
    func testNoticeSurvivesTranscriptParsing() throws {
        let escaped = block
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        let line = #"{"type":"user","message":{"content":"\#(escaped)"}}"#
        let turn = try XCTUnwrap(TranscriptReader.turns(text: line, tool: .claude).turns.first)
        XCTAssertEqual(turn.role, .toolResult)
        XCTAssertEqual(turn.notice?.taskId, "bkgxr69vu")
        // 지시 턴과 짝지을 열쇠가 실려 있어야 한다.
        XCTAssertEqual(turn.toolUseId, "toolu_01SqmFhVSpuKNfXcW9dMJggt")
    }

    /// 지시(tool_use id)와 결과(tool-use-id)가 같은 열쇠로 만나는지 — 잇기의 전부.
    func testDispatchAndNoticePairByToolUseId() {
        let escaped = block
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        let text = [
            #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"toolu_01SqmFhVSpuKNfXcW9dMJggt","name":"Agent","input":{"subagent_type":"Explore","prompt":"레포 훑어","description":"레포 조사"}}]}}"#,
            #"{"type":"user","message":{"content":"\#(escaped)"}}"#,
        ].joined(separator: "\n")
        let turns = TranscriptReader.turns(text: text, tool: .claude).turns
        let dispatch = turns.first { $0.speech?.kind == .dispatch }
        let result = turns.first { $0.notice != nil }
        XCTAssertNotNil(dispatch?.toolUseId)
        XCTAssertEqual(dispatch?.toolUseId, result?.notice?.toolUseId)
    }
}
