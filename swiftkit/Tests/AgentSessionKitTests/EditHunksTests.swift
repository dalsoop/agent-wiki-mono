import XCTest
@testable import AgentSessionKit

/// "이 에이전트가 뭘 바꿨나" 는 세션 기록에만 있다 — 커밋됐거나, 여러 에이전트가 같은
/// 파일을 만졌거나, 되돌려진 편집은 git 워킹트리에 흔적이 없다.
final class EditHunksTests: XCTestCase {
    private func turns(_ name: String, _ input: String) -> [TranscriptReader.Turn] {
        let line = #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"\#(name)","input":\#(input)}]}}"#
        return TranscriptReader.turns(text: line, tool: .claude).turns
    }

    func testEditCapturesBeforeAndAfter() throws {
        let t = try XCTUnwrap(turns("Edit", #"{"file_path":"/a.swift","old_string":"let x = 1","new_string":"let x = 2"}"#).first)
        let hunk = try XCTUnwrap(t.editHunks.first)
        XCTAssertEqual(hunk.before, "let x = 1")
        XCTAssertEqual(hunk.after, "let x = 2")
        XCTAssertFalse(hunk.isCreation)
    }

    func testMultiEditCapturesEveryHunk() {
        let input = #"{"file_path":"/a.swift","edits":[{"old_string":"a","new_string":"b"},{"old_string":"c","new_string":"d"}]}"#
        XCTAssertEqual(turns("MultiEdit", input).first?.editHunks.count, 2)
    }

    /// Write 는 이전 내용이 없다 — diff 가 아니라 생성이라고 말해야 한다.
    func testWriteIsCreation() throws {
        let t = try XCTUnwrap(turns("Write", #"{"file_path":"/new.md","content":"새 문서 본문"}"#).first)
        let hunk = try XCTUnwrap(t.editHunks.first)
        XCTAssertTrue(hunk.isCreation)
        XCTAssertEqual(hunk.after, "새 문서 본문")
    }

    func testReadAndBashProduceNoHunks() {
        XCTAssertTrue(turns("Read", #"{"file_path":"/a.md"}"#).first?.editHunks.isEmpty ?? false)
        XCTAssertTrue(turns("Bash", #"{"command":"ls"}"#).first?.editHunks.isEmpty ?? false)
    }

    /// 한 파일의 편집이 여럿이면 최근 것이 위로 — 화면이 그 순서로 보여준다.
    func testForFileSortsMostRecentFirst() {
        let text = [
            #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/a.swift","old_string":"1","new_string":"2"}}]}}"#,
            #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/a.swift","old_string":"2","new_string":"3"}}]}}"#,
        ].joined(separator: "\n")
        let all = TranscriptReader.turns(text: text, tool: .claude).turns
        let hunks = EditHunks.forFile("/a.swift", turns: all)
        XCTAssertEqual(hunks.count, 2)
        XCTAssertEqual(hunks.first?.after, "3")   // 최근 편집
    }

    func testLineDiffMarksAddedAndRemoved() {
        let d = EditHunks.lineDiff(before: "keep\nold", after: "keep\nnew")
        XCTAssertTrue(d.contains { $0.kind == .removed && $0.text == "old" })
        XCTAssertTrue(d.contains { $0.kind == .added && $0.text == "new" })
        XCTAssertTrue(d.contains { $0.kind == .context && $0.text == "keep" })
    }
}
