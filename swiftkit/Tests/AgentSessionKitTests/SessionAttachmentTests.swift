import XCTest
@testable import AgentSessionKit

/// 대화를 보는 화면에서 **사람 말이 사라지는 것**보다 나쁜 결함은 없다.
/// 실측(2026-08-04, 최근 세션 15개 중 9개): queued_command 18건 · edited_text_file 73건(.md 18)
/// 이 전부 `type:"attachment"` 줄이라 리더가 통째로 버리고 있었다.
final class SessionAttachmentTests: XCTestCase {
    func testQueuedHumanPromptBecomesUserTurn() throws {
        let line = #"{"type":"attachment","attachment":{"type":"queued_command","prompt":"머지하고 진행해봐","origin":{"kind":"human"}}}"#
        let turn = try XCTUnwrap(TranscriptReader.turns(text: line, tool: .claude).turns.first)
        XCTAssertEqual(turn.role, .user)
        XCTAssertEqual(turn.text, "머지하고 진행해봐")
    }

    /// 사람이 친 게 아닌 자동 주입 명령까지 사용자 발화로 세우면 안 된다.
    func testNonHumanQueuedCommandIsIgnored() {
        let line = #"{"type":"attachment","attachment":{"type":"queued_command","prompt":"auto","origin":{"kind":"system"}}}"#
        XCTAssertTrue(TranscriptReader.turns(text: line, tool: .claude).turns.isEmpty)
    }

    func testAttachedFileSurfacesWithSnippet() throws {
        let line = #"{"type":"attachment","attachment":{"type":"edited_text_file","filename":"/ws/docs/plan.md","snippet":"1\tplan"}}"#
        let turn = try XCTUnwrap(TranscriptReader.turns(text: line, tool: .claude).turns.first)
        let file = try XCTUnwrap(turn.attachedFile)
        XCTAssertEqual(file.path, "/ws/docs/plan.md")
        XCTAssertEqual(file.name, "plan.md")
        XCTAssertTrue(file.isDocument)          // 문서는 코드와 갈라 보여야 한다
        XCTAssertEqual(file.snippet, "1\tplan")
    }

    func testCodeAttachmentIsNotDocument() throws {
        let line = #"{"type":"attachment","attachment":{"type":"edited_text_file","filename":"/ws/App.swift"}}"#
        let turn = try XCTUnwrap(TranscriptReader.turns(text: line, tool: .claude).turns.first)
        XCTAssertEqual(turn.attachedFile?.isDocument, false)
    }

    /// 스킬 목록·툴 목록·리마인더까지 실으면 대화가 다시 잡음에 묻힌다.
    func testSystemAttachmentsAreDropped() {
        for kind in ["skill_listing", "task_reminder", "deferred_tools_delta", "agent_listing_delta"] {
            let line = #"{"type":"attachment","attachment":{"type":"\#(kind)","content":"x"}}"#
            XCTAssertTrue(TranscriptReader.turns(text: line, tool: .claude).turns.isEmpty, kind)
        }
    }

    /// 붙은 것도 대화 흐름 안 제자리에 서야 한다(발언 사이 순서 보존).
    func testAttachmentKeepsPositionInConversation() {
        let text = [
            #"{"type":"user","message":{"content":"이거 봐줘"}}"#,
            #"{"type":"attachment","attachment":{"type":"edited_text_file","filename":"/a.md"}}"#,
            #"{"type":"assistant","message":{"content":[{"type":"text","text":"읽었습니다"}]}}"#,
        ].joined(separator: "\n")
        let turns = TranscriptReader.turns(text: text, tool: .claude).turns
        XCTAssertEqual(turns.count, 3)
        XCTAssertEqual(turns[1].attachedFile?.name, "a.md")
    }
}
