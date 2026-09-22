import XCTest
@testable import RoomKit

final class RoomSessionIDTests: XCTestCase {
    func testPtyFormat() {
        let id = RoomSessionID.newPty()
        XCTAssertTrue(id.value.hasPrefix("pty-"))
        XCTAssertEqual(id.value.count, "pty-".count + 36) // UUID 길이
    }

    func testExecFormat() {
        let id = RoomSessionID.newExec()
        XCTAssertTrue(id.value.hasPrefix("exec-"))
    }

    func testCodable() throws {
        let original = RoomSessionID("pty-test-123")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RoomSessionID.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func testEquality() {
        let a = RoomSessionID("pty-abc")
        let b = RoomSessionID("pty-abc")
        let c = RoomSessionID("pty-def")
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testHashable() {
        let id = RoomSessionID("exec-hash")
        var set = Set<RoomSessionID>()
        set.insert(id)
        XCTAssertTrue(set.contains(id))
    }
}
