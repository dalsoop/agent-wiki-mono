import XCTest
@testable import InteropKit

final class OriginRefTests: XCTestCase {
    // 기본 Codable(camelCase) round-trip. 출처 앱이 인코딩하고 도착 앱이 디코딩하는
    // typed edge 에서 키 이름이 어긋나면 역류가 죽는다 — 계약이므로 고정한다.
    func testRoundTrip() throws {
        let origin = OriginRef(
            app: "agent-chat", roomID: "room-1",
            messageID: "msg-1", replyTo: "parent-msg"
        )
        let data = try JSONEncoder().encode(origin)
        let back = try JSONDecoder().decode(OriginRef.self, from: data)
        XCTAssertEqual(back, origin)
    }

    // camelCase 키가 JSON 에 그대로 나간다 — 다른 앱이 디코딩할 수 있게.
    func testCamelCaseKeys() throws {
        let origin = OriginRef(app: "agent-chat", roomID: "r", messageID: "m")
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(origin)) as? [String: Any]
        XCTAssertEqual(json?["app"] as? String, "agent-chat")
        XCTAssertEqual(json?["roomID"] as? String, "r")
        XCTAssertEqual(json?["messageID"] as? String, "m")
        XCTAssertNil(json?["replyTo"])
    }

    // replyTo 는 선택 — 출처 메시지가 스레드 뿌리면 없다.
    func testOptionalReplyTo() throws {
        let data = Data(#"{"app":"a","roomID":"r","messageID":"m"}"#.utf8)
        let back = try JSONDecoder().decode(OriginRef.self, from: data)
        XCTAssertNil(back.replyTo)
        XCTAssertEqual(back.app, "a")
    }
}
