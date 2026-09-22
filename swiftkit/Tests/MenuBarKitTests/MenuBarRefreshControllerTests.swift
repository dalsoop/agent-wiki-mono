import XCTest
@testable import MenuBarKit

final class MenuBarRefreshControllerTests: XCTestCase {
    @MainActor
    func testTriggerRefreshRunsRefreshAndAfterHook() async {
        var refreshCount = 0
        var afterCount = 0
        let controller = MenuBarRefreshController(
            refresh: { refreshCount += 1 },
            afterRefresh: { afterCount += 1 }
        )
        controller.triggerRefresh()
        // 백그라운드 Task 완료를 기다린다.
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(refreshCount, 1)
        XCTAssertEqual(afterCount, 1)
    }

    @MainActor
    func testTimerFiresPeriodically() async {
        var count = 0
        let controller = MenuBarRefreshController(refresh: { count += 1 })
        controller.restart(interval: 0.05)
        try? await Task.sleep(nanoseconds: 180_000_000)
        controller.stop()
        XCTAssertGreaterThanOrEqual(count, 2)
    }

    @MainActor
    func testZeroIntervalStopsTimer() async {
        var count = 0
        let controller = MenuBarRefreshController(refresh: { count += 1 })
        controller.restart(interval: 0)
        try? await Task.sleep(nanoseconds: 120_000_000)
        XCTAssertEqual(count, 0)
    }
}
