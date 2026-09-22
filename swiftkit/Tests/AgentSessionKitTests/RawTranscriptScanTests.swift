import Foundation
import XCTest
@testable import AgentSessionKit

final class RawTranscriptScanTests: XCTestCase {
    /// 픽스처 JSONL 에서 400자 넘는 tool_result 가 잘리지 않는 것 1건.
    /// TranscriptReader 는 toolTextCap(기본 400)으로 자르지만 RawTranscriptScan 은 원본 그대로 유지한다.
    func testToolResultExceeding400CharsIsNotTruncated() {
        let longBody = String(repeating: "가나다라마바사아자차", count: 80) // 800자
        XCTAssertGreaterThan(longBody.count, 400)

        let useJSON = #"{"type":"tool_use","id":"call_read_long","name":"Read","input":{"file_path":"/tmp/long.txt"}}"#
        let resultJSON = #"{"type":"tool_result","tool_use_id":"call_read_long","content":"\#(longBody)"}"#
        let line1 = #"{"type":"assistant","message":{"role":"assistant","content":[\#(useJSON)]}}"#
        let line2 = #"{"type":"user","message":{"role":"user","content":[\#(resultJSON)]}}"#
        let fixture = [line1, line2].joined(separator: "\n")

        // TranscriptReader 와 대조: 기본 toolTextCap(400)으로 잘림
        let readerResult = TranscriptReader.turns(text: fixture, tool: .claude)
        let toolResultTurn = readerResult.turns.first { $0.role == .toolResult }
        XCTAssertNotNil(toolResultTurn)
        XCTAssertLessThanOrEqual(toolResultTurn?.text.count ?? 0, 405)

        // RawTranscriptScan: 절단 없이 800자 원본 그대로
        let scanResult = RawTranscriptScan.scan(text: fixture)
        XCTAssertEqual(scanResult.toolPairs.count, 1)
        let pair = scanResult.toolPairs[0]
        XCTAssertEqual(pair.id, "call_read_long")
        XCTAssertEqual(pair.name, "Read")
        XCTAssertEqual(pair.result, longBody)
        XCTAssertEqual(pair.result.count, longBody.count)
        XCTAssertGreaterThan(pair.result.count, 400)
    }

    /// tool_use ↔ tool_result 짝 1건.
    func testToolUseAndResultPairing() {
        let useJSON = #"{"type":"tool_use","id":"toolu_01","name":"Read","input":{"file_path":"/repo/Sources/App.swift"}}"#
        let resultJSON = #"{"type":"tool_result","tool_use_id":"toolu_01","content":"import Foundation\n// body"}"#
        let line1 = #"{"type":"assistant","message":{"role":"assistant","content":[\#(useJSON)]}}"#
        let line2 = #"{"type":"user","message":{"role":"user","content":[\#(resultJSON)]}}"#
        let fixture = [line1, line2].joined(separator: "\n")

        var callbackCalled = false
        var callbackPair: RawTranscriptScan.ToolPair?
        let result = RawTranscriptScan.scan(text: fixture) { pair in
            callbackCalled = true
            callbackPair = pair
        }

        XCTAssertTrue(callbackCalled)
        XCTAssertEqual(result.toolPairs.count, 1)
        let pair = result.toolPairs[0]
        XCTAssertEqual(pair.id, "toolu_01")
        XCTAssertEqual(pair.name, "Read")
        XCTAssertEqual(pair.filePath, "/repo/Sources/App.swift")
        XCTAssertEqual(pair.result, "import Foundation\n// body")
        XCTAssertEqual(pair.isError, false)
        XCTAssertEqual(callbackPair, pair)
    }

    /// Bash 명령 추출 1건.
    func testBashCommandExtraction() {
        let b1JSON = #"{"type":"tool_use","id":"b1","name":"Bash","input":{"command":"git status -s"}}"#
        let r1JSON = #"{"type":"tool_result","tool_use_id":"b1","content":"M Package.swift"}"#
        let b2JSON = #"{"type":"tool_use","id":"b2","name":"Bash","input":{"command":"swift test --filter SmokeTests"}}"#
        let r2JSON = #"{"type":"tool_result","tool_use_id":"b2","content":"Executed 1 test"}"#
        let textJSON = #"{"type":"text","text":"모든 테스트 통과했습니다."}"#

        let line1 = #"{"type":"assistant","message":{"role":"assistant","content":[\#(b1JSON)]}}"#
        let line2 = #"{"type":"user","message":{"role":"user","content":[\#(r1JSON)]}}"#
        let line3 = #"{"type":"assistant","message":{"role":"assistant","content":[\#(b2JSON)]}}"#
        let line4 = #"{"type":"user","message":{"role":"user","content":[\#(r2JSON)]}}"#
        let line5 = #"{"type":"assistant","message":{"role":"assistant","content":[\#(textJSON)]}}"#
        let fixture = [line1, line2, line3, line4, line5].joined(separator: "\n")

        let result = RawTranscriptScan.scan(text: fixture)
        XCTAssertEqual(result.bashCommands, [
            "git status -s",
            "swift test --filter SmokeTests",
        ])
        XCTAssertEqual(result.lastAssistantText, "모든 테스트 통과했습니다.")
        XCTAssertEqual(result.toolPairs.count, 2)
        XCTAssertEqual(result.toolPairs[0].bashCommand, "git status -s")
        XCTAssertEqual(result.toolPairs[1].bashCommand, "swift test --filter SmokeTests")
    }
}
