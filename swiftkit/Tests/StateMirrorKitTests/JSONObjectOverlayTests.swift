import Foundation
import XCTest
@testable import StateMirrorKit

/// `mutateJSONObject` overlay 갱신 — GUI·CLI 두 writer 가 같은 미러를 나눠 쓸 때
/// 한쪽 키를 게시해도 다른 쪽 키가 지워지지 않는다는 계약.
final class JSONObjectOverlayTests: XCTestCase {
    private func overlay(_ app: String, keys: [String: Any]) throws {
        try StateMirror.mutateJSONObject(app: app, recovery: .replaceMalformed) { existing in
            var merged = existing ?? [:]
            for (key, value) in keys { merged[key] = value }
            return merged
        }
    }

    private func state(_ app: String) throws -> [String: Any]? {
        let url = URL(fileURLWithPath: StateMirror.path(app: app))
        guard let data = try? Data(contentsOf: url) else { return nil }
        let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return envelope?["state"] as? [String: Any]
    }

    func testSecondWriterPreservesFirstWriterKeys() throws {
        let app = "overlay-fixture-\(UUID().uuidString)"

        // writer A(GUI) — 자기 축 게시
        try overlay(app, keys: [
            "activeCount": 1,
            "handshake": "3초 전",
        ])
        // writer B(CLI) — 다른 축만 게시
        try overlay(app, keys: [
            "systemTunnelCount": 4,
            "settings": ["dnsLeakFirewall": false],
        ])

        let merged = try XCTUnwrap(state(app))
        XCTAssertEqual(merged["activeCount"] as? Int, 1)
        XCTAssertEqual(merged["handshake"] as? String, "3초 전")
        XCTAssertEqual(merged["systemTunnelCount"] as? Int, 4)
        XCTAssertNotNil(merged["settings"])
    }

    func testSameKeyLastWriterWins() throws {
        let app = "overlay-fixture-\(UUID().uuidString)"
        try overlay(app, keys: ["systemTunnelCount": 6])
        try overlay(app, keys: ["systemTunnelCount": 2])
        XCTAssertEqual(try state(app)?["systemTunnelCount"] as? Int, 2)
    }

    func testReplaceMalformedRecoversWithOverlay() throws {
        let app = "overlay-fixture-\(UUID().uuidString)"
        let url = URL(fileURLWithPath: StateMirror.path(app: app))
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{not-json".utf8).write(to: url)

        try overlay(app, keys: ["activeCount": 0])
        XCTAssertEqual(try state(app)?["activeCount"] as? Int, 0)
    }

    /// 정본 API 계약 — caller 는 merge 루프를 베끼지 않고 `publishOverlay` 만 부른다.
    /// 이 메서드가 다른 writer 의 키를 지우면 함대 전체가 다시 양방향 wipe 로 돌아간다.
    func testPublishOverlayPreservesOtherWriterKeys() throws {
        let app = "overlay-fixture-\(UUID().uuidString)"

        try overlay(app, keys: ["settings": ["dnsLeakFirewall": true]])  // writer A(CLI)
        try StateMirror.publishOverlay(app: app, recovery: .replaceMalformed, [           // writer B(GUI)
            "activeCount": 2,
            "settings": ["dnsLeakFirewall": false],   // 같은 키는 마지막 writer 승리
        ])

        let merged = try XCTUnwrap(state(app))
        XCTAssertEqual(merged["activeCount"] as? Int, 2)
        XCTAssertEqual((merged["settings"] as? [String: Any])?["dnsLeakFirewall"] as? Bool, false)
    }
}
