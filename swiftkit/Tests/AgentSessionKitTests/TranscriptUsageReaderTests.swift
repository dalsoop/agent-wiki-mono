import XCTest
@testable import AgentSessionKit

final class TranscriptUsageReaderTests: XCTestCase {
    func testReadsGrokResultLineWithAuthoritativeUsage() {
        let jsonl = """
        {"type":"system","subtype":"init","model":"grok-4.6"}
        {"type":"assistant","message":{"usage":{"input_tokens":100,"output_tokens":20}}}
        {"type":"result","subtype":"success","total_cost_usd":0.2264,"usage":{"input_tokens":152038,"output_tokens":9617}}
        """
        let usage = TranscriptUsageReader.readUsage(from: jsonl)
        XCTAssertEqual(usage.promptTokens, 152038)
        XCTAssertEqual(usage.completionTokens, 9617)
        XCTAssertEqual(usage.totalTokens, 161655)
        XCTAssertEqual(usage.costUSD, 0.2264)
    }

    func testReadsCodexTotalTokenUsageCumulative() {
        let jsonl = """
        {"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"output_tokens":30}}}}
        {"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":250,"output_tokens":90}}}}
        """
        let usage = TranscriptUsageReader.readUsage(from: jsonl)
        XCTAssertEqual(usage.promptTokens, 250)
        XCTAssertEqual(usage.completionTokens, 90)
        XCTAssertEqual(usage.totalTokens, 340)
    }

    func testSumsIncrementalTurnsWhenNoCumulativeResult() {
        let jsonl = """
        {"type":"assistant","message":{"usage":{"input_tokens":50,"output_tokens":10}}}
        {"type":"assistant","message":{"usage":{"input_tokens":80,"output_tokens":25}}}
        """
        let usage = TranscriptUsageReader.readUsage(from: jsonl)
        XCTAssertEqual(usage.promptTokens, 130)
        XCTAssertEqual(usage.completionTokens, 35)
        XCTAssertEqual(usage.totalTokens, 165)
    }

    func testReadsStandardTokenUsageObject() {
        let jsonl = """
        {"token_usage":{"prompt_tokens":1200,"completion_tokens":300,"total_tokens":1500},"total_cost_usd":0.015}
        """
        let usage = TranscriptUsageReader.readUsage(from: jsonl)
        XCTAssertEqual(usage.promptTokens, 1200)
        XCTAssertEqual(usage.completionTokens, 300)
        XCTAssertEqual(usage.totalTokens, 1500)
        XCTAssertEqual(usage.costUSD, 0.015)
    }

    func testReturnsZeroForPlainTextOrEmpty() {
        let text = """
        [orchestrator] cwd=/tmp
        Test passed.
        [orchestrator] commit complete
        """
        let usage = TranscriptUsageReader.readUsage(from: text)
        XCTAssertEqual(usage, .zero)
    }
}
