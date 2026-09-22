import XCTest
@testable import AgentSessionKit

final class TranscriptGrokStreamTests: XCTestCase {
    private func fixtureText() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/grok-stream-sample.jsonl")
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testGrokStreamDetection() throws {
        let text = try fixtureText()
        XCTAssertTrue(TranscriptGrok.isStreamingMessages(text: text))
        let acp = #"{"params":{"update":{"sessionUpdate":"user_message_chunk","content":{"type":"text","text":"확인해줘"}}}}"#
        XCTAssertFalse(TranscriptGrok.isStreamingMessages(text: acp))
        let acpTurns = TranscriptReader.turns(text: acp, tool: .grok)
        XCTAssertEqual(acpTurns.turns.map(\.role), [.user])
        XCTAssertEqual(acpTurns.turns.first?.text, "확인해줘")
    }

    func testGrokStreamRolesAndCounts() throws {
        let p = TranscriptReader.parsed(text: try fixtureText(), tool: .grok)
        XCTAssertEqual(
            p.turns.map(\.role),
            [.thinking, .assistant, .tool, .tool, .tool, .toolResult, .toolResult, .toolResult, .assistant])
        let counts = Dictionary(grouping: p.turns, by: \.role).mapValues(\.count)
        XCTAssertEqual(counts[.thinking], 1)
        XCTAssertEqual(counts[.assistant], 2)
        XCTAssertEqual(counts[.tool], 3)
        XCTAssertEqual(counts[.toolResult], 3)
        XCTAssertNil(counts[.user])
        XCTAssertEqual(p.turns[2].toolName, "read_file")
        XCTAssertTrue(p.turns[2].text.contains("/Users/fixture/workspace/Sources/Sample.swift"))
        XCTAssertEqual(p.turns[2].toolUseId, "call-read-1")
        XCTAssertEqual(p.turns[3].toolName, "grep")
        XCTAssertTrue(p.turns[3].text.contains("protocol NativeRule"))
        XCTAssertEqual(p.turns[4].toolName, "run_terminal_command")
        XCTAssertTrue(p.turns[4].text.hasPrefix("run_terminal_command: "))
        XCTAssertLessThanOrEqual(p.turns[4].text.count, "run_terminal_command: ".count + 120 + 1)
        XCTAssertTrue(p.turns[5].text.hasPrefix("↳"))
        XCTAssertTrue(p.turns[7].text.hasPrefix("error ↳"))
        XCTAssertFalse(p.turns[7].text.contains("more log"), "본문은 첫 줄만")
        let meta = try XCTUnwrap(p.grokStream)
        XCTAssertEqual(meta.sessionId, "00000000-0000-4000-8000-000000000001")
        XCTAssertEqual(meta.model, "grok-4.6")
        XCTAssertEqual(meta.cwd, "/Users/fixture/workspace")
        XCTAssertEqual(meta.resultSubtype, "success")
        XCTAssertEqual(meta.numTurns, 42)
        XCTAssertEqual(meta.durationMs, 905659)
        XCTAssertEqual(meta.totalCostUsd, 0.69461898)
    }

    func testGrokStreamAppended() throws {
        let fullText = try fixtureText()
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("grok-stream-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let lines = fullText.split(separator: "\n", omittingEmptySubsequences: true)
        let head = lines.prefix(2).joined(separator: "\n") + "\n"
        try head.write(to: tmp, atomically: true, encoding: .utf8)
        let first = TranscriptReader.appended(path: tmp.path, since: 0, tool: .grok)
        XCTAssertEqual(first.turns.map(\.role), [.thinking, .assistant, .tool, .tool, .tool])
        XCTAssertEqual(first.consumedOffset, head.utf8.count)

        let rest = lines.dropFirst(2).joined(separator: "\n") + "\n"
        let fh = try FileHandle(forWritingTo: tmp)
        fh.seekToEndOfFile()
        fh.write(Data(rest.utf8))
        try fh.close()

        let second = TranscriptReader.appended(
            path: tmp.path, since: first.consumedOffset, tool: .grok)
        XCTAssertEqual(second.turns.map(\.role), [.toolResult, .toolResult, .toolResult, .assistant])
        let full = TranscriptReader.turns(text: fullText, tool: .grok).turns
        XCTAssertEqual(
            (first.turns.map(\.role) + second.turns.map(\.role)),
            full.map(\.role))
        XCTAssertEqual(
            first.turns.map(\.text) + second.turns.map(\.text),
            full.map(\.text))
        XCTAssertEqual(second.grokStream?.resultSubtype, "success")
        XCTAssertEqual(second.grokStream?.numTurns, 42)
    }

    func testGrokStreamClippingKeepsToolUseName() throws {
        let blob = String(repeating: "B", count: 80_000)
        let assistant: [String: Any] = [
            "type": "assistant",
            "message": [
                "role": "assistant",
                "content": [
                    [
                        "type": "tool_use",
                        "id": "call-keep",
                        "name": "read_file",
                        "input": [
                            "target_file": "/Users/fixture/workspace/Huge.swift",
                            "patch": blob,
                        ],
                    ],
                    ["type": "text", "text": "ok"],
                ],
            ],
        ]
        let user: [String: Any] = [
            "type": "user",
            "message": [
                "role": "user",
                "content": [
                    [
                        "type": "tool_result",
                        "tool_use_id": "call-keep",
                        "is_error": false,
                        "content": blob + "\nsecond-line",
                    ],
                ],
            ],
        ]
        let initLine =
            #"{"type":"system","subtype":"init","session_id":"s","model":"grok-4.6","cwd":"/tmp"}"#
        let text = [
            initLine,
            try encodeJSON(assistant),
            try encodeJSON(user),
        ].joined(separator: "\n")
        XCTAssertGreaterThan(text.utf8.count, JSONLine.blobStringByteCap)
        let p = TranscriptReader.parsed(text: text, tool: .grok)
        let tool = try XCTUnwrap(p.turns.first { $0.role == .tool })
        XCTAssertEqual(tool.toolName, "read_file")
        XCTAssertEqual(tool.toolUseId, "call-keep")
        XCTAssertTrue(tool.text.contains("Huge.swift"))
        let result = try XCTUnwrap(p.turns.first { $0.role == .toolResult })
        XCTAssertTrue(result.text.hasPrefix("↳ B"))
        XCTAssertFalse(result.text.contains("second-line"))
    }

    private func encodeJSON(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object)
        return String(decoding: data, as: UTF8.self)
    }
}
