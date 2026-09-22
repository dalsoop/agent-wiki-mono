import XCTest
@testable import HostGovernanceKit

final class HostGovernanceKitTests: XCTestCase {
    func testHostHardwareProfileCurrent() {
        let profile = HostHardwareProfile.current()
        XCTAssertGreaterThan(profile.totalLogicalCores, 0)
        XCTAssertGreaterThan(profile.performanceCores, 0)
        XCTAssertGreaterThanOrEqual(profile.safeCompileQuota, 1)
    }

    func testHostCompileGateSnapshot() {
        let okSnap = HostCompileGate.snapshot(load1: 1.0, frontendCount: 0, ncpu: 8)
        XCTAssertFalse(okSnap.hold)
        XCTAssertEqual(okSnap.reason, "ok")

        let holdSnap = HostCompileGate.snapshot(load1: 10.0, frontendCount: 8, ncpu: 8)
        XCTAssertTrue(holdSnap.hold)
        XCTAssertTrue(holdSnap.reason.contains("swift-frontend"))
    }

    func testMachineCompileLockAcquireAndRelease() throws {
        let lock = MachineCompileLock()
        var executed = false

        try lock.withLock(timeout: 5.0) {
            executed = true
        }

        XCTAssertTrue(executed)
    }

    func testMachineCompileLockReentrancySeparateFds() throws {
        let lock = MachineCompileLock()
        var runCount = 0

        // 락이 정상적으로 풀린 후 다시 획득 가능한지 검증
        try lock.withLock(timeout: 2.0) {
            runCount += 1
        }

        try lock.withLock(timeout: 2.0) {
            runCount += 1
        }

        XCTAssertEqual(runCount, 2)
    }
}
