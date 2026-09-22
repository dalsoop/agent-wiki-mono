import XCTest
@testable import MCPSupport

final class MCPArgsTests: XCTestCase {
    func testAcceptsNormalValues() {
        XCTAssertEqual(MCPArgs.int(5), 5)
        XCTAssertEqual(MCPArgs.int(NSNumber(value: 5)), 5)
        XCTAssertEqual(MCPArgs.int(NSNumber(value: 5.0)), 5)
        XCTAssertEqual(MCPArgs.int(5.7), 5)
        XCTAssertEqual(MCPArgs.int("7"), 7)
        XCTAssertEqual(MCPArgs.int(NSNumber(value: Int.max)), Int.max)
    }

    func testRejectsOutOfRangeDoubleInsteadOfTrapping() {
        // The bug: Int(1e308) is a trapping conversion that aborts the server.
        XCTAssertNil(MCPArgs.int(1e308))
        XCTAssertNil(MCPArgs.int(NSNumber(value: 1e308)))
        XCTAssertNil(MCPArgs.int(-1e308))
    }

    func testRejectsNonFiniteAndBoolAndGarbage() {
        XCTAssertNil(MCPArgs.int(Double.nan))
        XCTAssertNil(MCPArgs.int(Double.infinity))
        XCTAssertNil(MCPArgs.int(true))
        XCTAssertNil(MCPArgs.int("nope"))
        XCTAssertNil(MCPArgs.int(nil))
    }

    func testBoolCoercion() {
        XCTAssertEqual(MCPArgs.bool(true), true)
        XCTAssertEqual(MCPArgs.bool(false), false)
        XCTAssertEqual(MCPArgs.bool(NSNumber(value: true)), true)
        XCTAssertEqual(MCPArgs.bool("true"), true)
        XCTAssertEqual(MCPArgs.bool("false"), false)
        XCTAssertNil(MCPArgs.bool("yes"))
        XCTAssertNil(MCPArgs.bool(1))
        XCTAssertNil(MCPArgs.bool(nil))
    }
}

final class MCPJSONTests: XCTestCase {
    func testRejectsNonFiniteNumbersInsteadOfRaising() {
        XCTAssertNil(MCPJSON.data(["x": Double.nan]))
        XCTAssertNil(MCPJSON.data(["x": Double.infinity]))
        XCTAssertTrue(MCPJSON.string(["x": Double.nan]).contains("not serializable"))
    }

    func testSerializesValidObjects() {
        XCTAssertNotNil(MCPJSON.data(["a": 1, "b": "x"]))
        XCTAssertEqual(MCPJSON.string(["a": 1]), "{\"a\":1}")
    }
}
