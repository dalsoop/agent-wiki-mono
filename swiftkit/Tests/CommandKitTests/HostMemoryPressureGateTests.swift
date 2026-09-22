import XCTest
@testable import CommandKit

final class HostMemoryPressureGateTests: XCTestCase {
    func testHoldWhenAvailableMemoryBelow2GB() {
        let oneGB: UInt64 = 1024 * 1024 * 1024
        let total: UInt64 = 32 * 1024 * 1024 * 1024
        let s = HostMemoryPressureGate.snapshot(
            availableBytes: oneGB,
            totalBytes: total,
            thresholdBytes: HostMemoryPressureGate.minimumAvailableMemoryBytes
        )
        XCTAssertTrue(s.hold)
        XCTAssertTrue(s.reason.contains("available memory low"))
        XCTAssertEqual(s.availableBytes, oneGB)
        XCTAssertEqual(s.thresholdBytes, HostMemoryPressureGate.minimumAvailableMemoryBytes)
    }

    func testPassWhenAvailableMemoryAbove2GB() {
        let threeGB: UInt64 = 3 * 1024 * 1024 * 1024
        let total: UInt64 = 32 * 1024 * 1024 * 1024
        let s = HostMemoryPressureGate.snapshot(
            availableBytes: threeGB,
            totalBytes: total,
            thresholdBytes: HostMemoryPressureGate.minimumAvailableMemoryBytes
        )
        XCTAssertFalse(s.hold)
        XCTAssertEqual(s.reason, "ok")
    }

    func testHoldAtExactBoundary() {
        // Less than threshold is hold
        let threshold = HostMemoryPressureGate.minimumAvailableMemoryBytes
        let sUnder = HostMemoryPressureGate.snapshot(
            availableBytes: threshold - 1,
            totalBytes: 32 * 1024 * 1024 * 1024,
            thresholdBytes: threshold
        )
        XCTAssertTrue(sUnder.hold)

        let sExact = HostMemoryPressureGate.snapshot(
            availableBytes: threshold,
            totalBytes: 32 * 1024 * 1024 * 1024,
            thresholdBytes: threshold
        )
        XCTAssertFalse(sExact.hold)
    }

    func testLiveKernelCheckReturnsValidSnapshot() {
        let s = HostMemoryPressureGate.check()
        // Live kernel check on macOS should report non-zero total and available memory
        XCTAssertGreaterThan(s.totalBytes, 0)
        XCTAssertGreaterThan(s.availableBytes, 0)
        XCTAssertEqual(s.thresholdBytes, HostMemoryPressureGate.minimumAvailableMemoryBytes)
    }
}
