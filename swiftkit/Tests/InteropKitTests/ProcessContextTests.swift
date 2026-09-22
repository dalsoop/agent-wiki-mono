import XCTest
@testable import InteropKit

final class ProcessContextTests: XCTestCase {
    func testProcessContextDataRunnerTaskLocalIsolation() async {
        let stubDataRunner: ProcessDataRunner = { _, _ in
            (0, Data("mock-data".utf8))
        }

        XCTAssertNil(ProcessContext.currentDataRunner)

        await ProcessContext.$currentDataRunner.withValue(stubDataRunner) {
            XCTAssertNotNil(ProcessContext.currentDataRunner)
            let result = ProcessContext.currentDataRunner?("/bin/echo", ["hello"])
            XCTAssertEqual(result?.0, 0)
            XCTAssertEqual(result.map { String(decoding: $0.1, as: UTF8.self) }, "mock-data")
        }

        XCTAssertNil(ProcessContext.currentDataRunner)
    }

    func testProcessContextStringRunnerTaskLocalIsolation() async {
        let stubStringRunner: ProcessStringRunner = { _, _ in
            (0, "mock-string")
        }

        XCTAssertNil(ProcessContext.currentStringRunner)

        await ProcessContext.$currentStringRunner.withValue(stubStringRunner) {
            XCTAssertNotNil(ProcessContext.currentStringRunner)
            let result = ProcessContext.currentStringRunner?("/bin/echo", ["hello"])
            XCTAssertEqual(result?.0, 0)
            XCTAssertEqual(result?.1, "mock-string")
        }

        XCTAssertNil(ProcessContext.currentStringRunner)
    }

    func testDefaultProcessRunnerExecutesCommand() {
        let runner = DefaultProcessRunner()
        let (code, data) = runner.run("/bin/echo", ["ping"])
        XCTAssertEqual(code, 0)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("ping"))
    }
}
