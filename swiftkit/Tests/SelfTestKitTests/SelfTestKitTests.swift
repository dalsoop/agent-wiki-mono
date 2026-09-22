import XCTest
@testable import SelfTestKit

final class SelfTestKitTests: XCTestCase {
    func testReportCounts() {
        let r = SelfTestReport(cases: [
            .check("a", true, detail: ""),
            .check("b", false, detail: ""),
            .check("c", true, detail: ""),
        ])
        XCTAssertEqual(r.passed, 2)
        XCTAssertEqual(r.failed, 1)
        XCTAssertFalse(r.allPassed)
    }

    func testEqualHelper() {
        let pass = SelfTestCase.equal("x", expected: "1", actual: "1")
        XCTAssertTrue(pass.passed)
        let fail = SelfTestCase.equal("y", expected: "1", actual: "2")
        XCTAssertFalse(fail.passed)
    }

    func testAllPassed() {
        let r = SelfTestReport(cases: [
            .check("a", true, detail: ""),
            .check("b", true, detail: ""),
        ])
        XCTAssertTrue(r.allPassed)
        XCTAssertEqual(r.passed, 2)
        XCTAssertEqual(r.failed, 0)
    }
}
