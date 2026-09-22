import XCTest
@testable import FleetCockpitPerspectiveKit

final class UnifiedBarItemTests: XCTestCase {
    func testBarModeCycle() {
        var mode: BarMode = .appBar
        XCTAssertEqual(mode.next(), .agentBar)
        XCTAssertEqual(mode.previous(), .roomBar)

        mode = .agentBar
        XCTAssertEqual(mode.next(), .roomBar)
        XCTAssertEqual(mode.previous(), .appBar)

        mode = .roomBar
        XCTAssertEqual(mode.next(), .appBar)
        XCTAssertEqual(mode.previous(), .agentBar)
    }

    func testUnifiedBarItemSubjobFormatting() {
        let itemWithoutSubjobs = UnifiedBarItem(
            id: "test-1",
            title: "App",
            icon: .symbol("star")
        )
        XCTAssertFalse(itemWithoutSubjobs.hasSubjobs)
        XCTAssertNil(itemWithoutSubjobs.subjobString)

        let itemWithQueuedSubjobs = UnifiedBarItem(
            id: "test-2",
            title: "Room",
            icon: .symbol("house"),
            subjobCount: 5,
            runningSubjobCount: 0
        )
        XCTAssertTrue(itemWithQueuedSubjobs.hasSubjobs)
        XCTAssertEqual(itemWithQueuedSubjobs.subjobString, "↳ 5")

        let itemWithRunningSubjobs = UnifiedBarItem(
            id: "test-3",
            title: "Room 2",
            icon: .symbol("house"),
            subjobCount: 5,
            runningSubjobCount: 2
        )
        XCTAssertTrue(itemWithRunningSubjobs.hasSubjobs)
        XCTAssertEqual(itemWithRunningSubjobs.subjobString, "↳ 5 (2 run)")
    }
}
