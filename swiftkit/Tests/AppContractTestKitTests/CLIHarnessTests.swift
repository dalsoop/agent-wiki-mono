import Foundation
import XCTest
@testable import AppContractTestKit

final class CLIHarnessTests: XCTestCase {
    func testCLIResultSucceeded() {
        let result = CLIResult(status: 0, stdout: "ok", stderr: "")
        XCTAssertTrue(result.succeeded)
    }

    func testCLIResultFailed() {
        let result = CLIResult(status: 1, stdout: "", stderr: "error")
        XCTAssertFalse(result.succeeded)
    }

    func testCLIResultJson() throws {
        let jsonString = "{\"key\":\"value\"}"
        let result = CLIResult(status: 0, stdout: jsonString, stderr: "")
        let parsed = try result.jsonObject()
        XCTAssertEqual(parsed["key"] as? String, "value")
    }

    func testCLIResultJsonEnvelope() throws {
        let jsonEnvelope = "{\"ok\":true,\"result\":{\"status\":\"active\",\"count\":42}}"
        let result = CLIResult(status: 0, stdout: jsonEnvelope, stderr: "")
        let unwrapped = try result.jsonObject()
        XCTAssertEqual(unwrapped["status"] as? String, "active")
        XCTAssertEqual(unwrapped["count"] as? Int, 42)
    }

    func testCLIResultJsonArrayEnvelope() throws {
        let jsonEnvelope = "{\"ok\":true,\"result\":[\"item1\",\"item2\"]}"
        let result = CLIResult(status: 0, stdout: jsonEnvelope, stderr: "")
        let unwrapped = try result.jsonArray()
        XCTAssertEqual(unwrapped.count, 2)
        XCTAssertEqual(unwrapped[0] as? String, "item1")
    }

    func testCLIHarnessErrorDescriptions() {
        let notFound = CLIHarnessError.binaryNotFound("/path/to/binary")
        XCTAssertTrue(notFound.description.contains("/path/to/binary"))

        let notAnObject = CLIHarnessError.notAnObject("invalid string")
        XCTAssertTrue(notAnObject.description.contains("invalid string"))

        let notAnArray = CLIHarnessError.notAnArray("invalid array")
        XCTAssertTrue(notAnArray.description.contains("invalid array"))
    }
}
