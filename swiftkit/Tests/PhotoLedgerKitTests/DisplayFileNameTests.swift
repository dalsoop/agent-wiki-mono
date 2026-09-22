import XCTest
@testable import PhotoLedgerKit

final class DisplayFileNameTests: XCTestCase {
    func testCleanNameStays() {
        XCTAssertEqual(DisplayFileName.title(name: "민수.jpg"), "민수.jpg")
        XCTAssertEqual(DisplayFileName.title(name: "20150605_012908.jpg"), "20150605_012908.jpg")
    }

    func testReplacementFallsBackToParentAndStem() {
        let broken = "122A9406 \u{FFFD}뚜겸.jpeg"
        let rel = "20_area/photo/웨딩/가을 웨딩/\(broken)"
        XCTAssertEqual(
            DisplayFileName.title(name: broken, rel: rel),
            "가을 웨딩 · 122A9406.jpeg"
        )
        XCTAssertTrue(
            DisplayFileName.matchesSearch(name: broken, rel: rel, id: "abc123", query: "가을")
        )
    }

    func testReplacementWithoutParentUsesStem() {
        XCTAssertEqual(
            DisplayFileName.title(name: "122A9406 \u{FFFD}x.jpeg"),
            "122A9406.jpeg"
        )
    }

    func testEmptyName() {
        XCTAssertEqual(DisplayFileName.title(name: "  "), "")
        XCTAssertEqual(DisplayFileName.shown(name: "  ", rel: "", fallbackID: "id1"), "id1")
    }
}
