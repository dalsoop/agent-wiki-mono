import XCTest
@testable import DevToolsAgentKit

final class DevToolsBridgeTests: XCTestCase {
    func testPathsShareRootAndApp() {
        XCTAssertTrue(DevToolsBridge.appDir(app: "pim-mail").hasSuffix(".swift-devtools/pim-mail"))
        XCTAssertTrue(DevToolsBridge.heartbeatPath(app: "a").hasSuffix("a/heartbeat.json"))
        XCTAssertTrue(DevToolsBridge.logsPath(app: "a").hasSuffix("a/logs.jsonl"))
    }

    func testJSONLRoundTrip() {
        let records = [
            DevToolsBridge.LogRecord(date: Date(timeIntervalSince1970: 1000), level: "info", category: "net", message: "hello"),
            DevToolsBridge.LogRecord(date: Date(timeIntervalSince1970: 2000), level: "error", category: "db", message: "줄바꿈 없는 한글 메시지"),
        ]
        let decoded = DevToolsBridge.decodeLines(DevToolsBridge.encodeLines(records))
        XCTAssertEqual(decoded, records)
    }

    func testDecodeSkipsTruncatedLine() {
        var data = DevToolsBridge.encodeLines([
            DevToolsBridge.LogRecord(date: Date(timeIntervalSince1970: 0), level: "info", category: "c", message: "ok")
        ])
        data.append(Data("{\"date\":\"2026-07-".utf8))  // 동시 쓰기 중 잘린 마지막 줄
        XCTAssertEqual(DevToolsBridge.decodeLines(data).count, 1)
    }

    func testCappedTailKeepsRecentOnly() {
        let records = (0..<100).map {
            DevToolsBridge.LogRecord(date: Date(timeIntervalSince1970: TimeInterval($0)), level: "info", category: "c", message: "\($0)")
        }
        XCTAssertEqual(DevToolsBridge.cappedTail(records, maxLines: 100, keepLines: 50).count, 100)
        let capped = DevToolsBridge.cappedTail(records, maxLines: 99, keepLines: 50)
        XCTAssertEqual(capped.count, 50)
        XCTAssertEqual(capped.last?.message, "99")
        XCTAssertEqual(capped.first?.message, "50")
    }

    func testHeartbeatRoundTrip() throws {
        let hb = DevToolsBridge.Heartbeat(app: "x", pid: 42, subsystem: "net.ranode.x", startedAt: "s", updatedAt: "u")
        let back = try DevToolsBridge.decoder.decode(
            DevToolsBridge.Heartbeat.self, from: DevToolsBridge.encoder.encode(hb))
        XCTAssertEqual(back, hb)
    }
}
