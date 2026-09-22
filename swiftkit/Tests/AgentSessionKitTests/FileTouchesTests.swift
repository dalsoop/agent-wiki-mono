import XCTest
@testable import AgentSessionKit

/// "이 에이전트가 뭘 읽고 뭘 고쳤나" — 읽기가 빠지면 md 를 스무 개 읽어도 화면은 비어 있다.
final class FileTouchesTests: XCTestCase {
    private func claudeTool(_ name: String, _ input: String) -> String {
        #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"\#(name)","input":\#(input)}]}}"#
    }

    func testReadAndWriteAreCountedSeparately() {
        let text = [
            claudeTool("Read", #"{"file_path":"/ws/docs/plan.md"}"#),
            claudeTool("Read", #"{"file_path":"/ws/docs/plan.md"}"#),
            claudeTool("Edit", #"{"file_path":"/ws/Sources/App.swift"}"#),
        ].joined(separator: "\n")
        let touches = FileTouches.collect(TranscriptReader.turns(text: text, tool: .claude).turns)
        let byPath = Dictionary(uniqueKeysWithValues: touches.map { ($0.path, $0) })

        XCTAssertEqual(byPath["/ws/docs/plan.md"]?.reads, 2)
        XCTAssertEqual(byPath["/ws/docs/plan.md"]?.writes, 0)
        XCTAssertEqual(byPath["/ws/docs/plan.md"]?.isEdited, false)
        XCTAssertEqual(byPath["/ws/Sources/App.swift"]?.writes, 1)
        XCTAssertEqual(byPath["/ws/Sources/App.swift"]?.isEdited, true)
    }

    /// 가장 최근에 만진 파일이 위로 — 사이드바가 그 순서로 보여준다.
    func testMostRecentTouchSortsFirst() {
        let text = [
            claudeTool("Read", #"{"file_path":"/ws/a.md"}"#),
            claudeTool("Write", #"{"file_path":"/ws/b.swift"}"#),
        ].joined(separator: "\n")
        XCTAssertEqual(FileTouches.collect(TranscriptReader.turns(text: text, tool: .claude).turns)
            .map(\.path), ["/ws/b.swift", "/ws/a.md"])
    }

    func testMultiEditCollectsEveryTarget() {
        let text = claudeTool("MultiEdit", #"{"edits":[{"file_path":"/ws/x.swift"},{"file_path":"/ws/y.swift"}]}"#)
        XCTAssertEqual(Set(FileTouches.collect(TranscriptReader.turns(text: text, tool: .claude).turns).map(\.path)),
                       ["/ws/x.swift", "/ws/y.swift"])
    }

    /// 상대 경로·비파일 인자는 경로가 아니다 — 과대집계는 목록을 못 믿게 만든다.
    func testNonPathArgumentsAreIgnored() {
        let text = [
            claudeTool("Bash", #"{"command":"ls -al /ws"}"#),
            claudeTool("Grep", #"{"pattern":"TODO"}"#),
        ].joined(separator: "\n")
        XCTAssertTrue(FileTouches.collect(TranscriptReader.turns(text: text, tool: .claude).turns).isEmpty)
    }

    /// codex 는 셸로 apply_patch 를 넘긴다 — 헤더가 유일하게 믿을 수 있는 편집 근거다.
    func testCodexApplyPatchCountsAsWrite() {
        let patch = "*** Begin Patch\\n*** Update File: /ws/Sources/Deck.swift\\n+ line\\n*** End Patch"
        let line = #"{"type":"event_msg","payload":{"type":"exec_command_end","command":["apply_patch","\#(patch)"]}}"#
        let touches = FileTouches.collect(TranscriptReader.turns(text: line, tool: .codex).turns)
        XCTAssertEqual(touches.first?.path, "/ws/Sources/Deck.swift")
        XCTAssertEqual(touches.first?.writes, 1)
        XCTAssertEqual(touches.first?.reads, 0)
    }

    func testShortPathKeepsTail() {
        XCTAssertEqual(FileTouches.shortPath("/a/b/c/d/e.swift"), "c/d/e.swift")
    }
}
