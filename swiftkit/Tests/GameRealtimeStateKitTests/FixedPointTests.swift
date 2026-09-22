import XCTest
@testable import GameRealtimeStateKit

final class FixedPointTests: XCTestCase {
    func testScaleAndOverflowAreExplicit() throws {
        XCTAssertEqual(
            try FixedPoint(rawValue: 1_024)
                .adding(FixedPoint(rawValue: 512))
                .rawValue,
            1_536
        )
        XCTAssertThrowsError(
            try FixedPoint(rawValue: Int32.max)
                .adding(FixedPoint(rawValue: 1))
        )
    }
}
