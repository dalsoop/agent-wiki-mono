import XCTest
@testable import GujoStoreOpsCore

final class StoreOpsOnboardingProbeTests: XCTestCase {
    func testPlaybookHasStableIds() {
        let ids = StoreOpsOnboardingPlaybook.steps.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
        XCTAssertTrue(ids.contains("token"))
        XCTAssertTrue(ids.contains("adb"))
        XCTAssertTrue(ids.contains("job-install"))
    }

    func testPlainTextNonEmpty() {
        let t = StoreOpsOnboardingPlaybook.plainText()
        XCTAssertTrue(t.contains("따라하기") || t.contains("온보딩"))
        XCTAssertTrue(t.contains("USB 디버깅") || t.contains("phone-setup") || t.contains("휴대폰"))
    }

    func testProbeTokenTodoWhenMissing() {
        var s = StoreOpsOnboardingSnapshot(tokenSet: false, healthOK: false)
        XCTAssertEqual(s.status(for: "token"), .todo)
        s.tokenSet = true
        s.healthOK = true
        XCTAssertEqual(s.status(for: "token"), .done)
    }

    func testInstallReadyBlockedWithoutServerDevice() {
        let s = StoreOpsOnboardingSnapshot(
            tokenSet: true, healthOK: true, packageCount: 3,
            adbAvailable: true, localReadyCount: 1, serverDeviceCount: 0
        )
        XCTAssertEqual(s.status(for: "installReady"), .blocked)
        XCTAssertEqual(s.status(for: "serverDevice"), .todo)
    }

    func testInstallReadyDoneWhenServerAndPackages() {
        let s = StoreOpsOnboardingSnapshot(
            tokenSet: true, healthOK: true, packageCount: 3,
            adbAvailable: true, localReadyCount: 1, serverDeviceCount: 1
        )
        XCTAssertEqual(s.status(for: "installReady"), .done)
        XCTAssertEqual(s.status(for: "doctor"), .done)
    }
}
