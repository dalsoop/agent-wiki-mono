import XCTest
@testable import CommandKit

final class CPUCapTests: XCTestCase {
    func testSafeJobCountCore4OrLess() {
        XCTAssertEqual(CPUCap.safeJobCount(ncpu: 1, environment: [:]), 1)
        XCTAssertEqual(CPUCap.safeJobCount(ncpu: 2, environment: [:]), 1)
        XCTAssertEqual(CPUCap.safeJobCount(ncpu: 3, environment: [:]), 2)
        XCTAssertEqual(CPUCap.safeJobCount(ncpu: 4, environment: [:]), 3)
    }

    func testSafeJobCountCore8OrLess() {
        XCTAssertEqual(CPUCap.safeJobCount(ncpu: 5, environment: [:]), 3)
        XCTAssertEqual(CPUCap.safeJobCount(ncpu: 8, environment: [:]), 3)
    }

    func testSafeJobCountCore9OrMoreCappedAt4() {
        XCTAssertEqual(CPUCap.safeJobCount(ncpu: 9, environment: [:]), 4)
        XCTAssertEqual(CPUCap.safeJobCount(ncpu: 16, environment: [:]), 4)
    }

    func testSWIFT_BUILD_JOBSWinsWhenPositive() {
        XCTAssertEqual(
            CPUCap.safeJobCount(ncpu: 16, environment: ["SWIFT_BUILD_JOBS": "8"]),
            8
        )
        XCTAssertEqual(
            CPUCap.safeJobCount(ncpu: 16, environment: ["SWIFT_BUILD_JOBS": "0"]),
            4
        )
    }

    func testWorkstationRunnerConcurrent() {
        XCTAssertEqual(
            CPUCap.safeWorkstationRunnerConcurrent(ncpu: 4, memoryBytes: 16_000_000_000),
            1
        )
        XCTAssertEqual(
            CPUCap.safeWorkstationRunnerConcurrent(ncpu: 8, memoryBytes: 8_000_000_000),
            1
        )
        XCTAssertEqual(
            CPUCap.safeWorkstationRunnerConcurrent(ncpu: 8, memoryBytes: 16_000_000_000),
            2
        )
    }
}
