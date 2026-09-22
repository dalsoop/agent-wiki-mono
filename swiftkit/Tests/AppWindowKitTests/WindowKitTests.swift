import XCTest
import AppKit
@testable import AppWindowKit

final class WindowKitTests: XCTestCase {
    @MainActor
    func testSingleInstanceGuardNoBundleIDIsNotDuplicate() {
        // 테스트 러너 번들엔 우리 bundle id 가 없으니 중복이 아니어야 한다(false).
        XCTAssertFalse(SingleInstanceGuard.isDuplicate(activateExisting: false))
    }

    @MainActor
    func testStandardDelegateDefaults() {
        let d = StandardWindowAppDelegate()
        XCTAssertEqual(d.activationPolicy, .regular)
        XCTAssertTrue(d.terminatesAfterLastWindowClosed)
        XCTAssertFalse(d.enforcesSingleInstance)
    }

    func testEvacuateResultStructure() {
        let result = RoomWindowEngine.EvacuateResult(
            unhiddenAppsCount: 2,
            unminimizedWindowsCount: 3,
            repositionedWindowsCount: 1
        )
        XCTAssertEqual(result.unhiddenAppsCount, 2)
        XCTAssertEqual(result.unminimizedWindowsCount, 3)
        XCTAssertEqual(result.repositionedWindowsCount, 1)
        XCTAssertEqual(result.totalCount, 6)
    }

    @MainActor
    func testEmergencyEvacuateAllRunsSafely() {
        let result = RoomWindowEngine.emergencyEvacuateAll()
        XCTAssertGreaterThanOrEqual(result.unhiddenAppsCount, 0)
        XCTAssertGreaterThanOrEqual(result.unminimizedWindowsCount, 0)
        XCTAssertGreaterThanOrEqual(result.repositionedWindowsCount, 0)
    }
}
