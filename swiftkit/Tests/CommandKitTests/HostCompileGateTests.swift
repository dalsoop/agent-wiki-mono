import XCTest
@testable import CommandKit

final class HostCompileGateTests: XCTestCase {
    func testLoadHighDoesNotHold() {
        let s = HostCompileGate.snapshot(load1: 54.5, frontendCount: 0, ncpu: 10)
        XCTAssertFalse(s.hold)
        XCTAssertEqual(s.ncpu, 10)
        XCTAssertGreaterThan(s.loadPerCore, 5)
        XCTAssertEqual(s.reason, "ok")
    }

    func testHoldWhenFrontendHigh() {
        let s = HostCompileGate.snapshot(load1: 1, frontendCount: 40, ncpu: 10)
        XCTAssertTrue(s.hold)
        XCTAssertTrue(s.reason.contains("swift-frontend"))
    }

    func testHoldWhenBothHighIsFrontendOnly() {
        let s = HostCompileGate.snapshot(load1: 20, frontendCount: 20, ncpu: 10)
        XCTAssertTrue(s.hold)
        XCTAssertFalse(s.reason.contains("20.0/10"))
        XCTAssertTrue(s.reason.contains("swift-frontend"))
    }

    func testOpenWhenBothLow() {
        let s = HostCompileGate.snapshot(load1: 2, frontendCount: 1, ncpu: 10)
        XCTAssertFalse(s.hold)
        XCTAssertEqual(s.reason, "ok")
    }

    func testBoundaryLoadIsOpen() {
        let s = HostCompileGate.snapshot(load1: 8.0, frontendCount: 0, ncpu: 10)
        XCTAssertFalse(s.hold)
    }

    func testBoundaryFrontendIsHold() {
        let s = HostCompileGate.snapshot(load1: 0, frontendCount: 10, ncpu: 10)
        XCTAssertTrue(s.hold)
    }

    func testFrontendBelowCoreCountIsOpen() {
        let s = HostCompileGate.snapshot(load1: 1, frontendCount: 8, ncpu: 10)
        XCTAssertFalse(s.hold)
    }
}
