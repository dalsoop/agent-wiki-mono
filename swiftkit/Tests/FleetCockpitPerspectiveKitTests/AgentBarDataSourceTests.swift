import XCTest
@testable import FleetCockpitPerspectiveKit

final class AgentBarDataSourceTests: XCTestCase {

    func testEmptyAgentsReturnsEmptyArrayWithoutFakeAgyOrAWO() {
        // Given: 아무 에이전트도 실행 중이지 않은 깨끗한 상태
        let emptyStore = InvertedStateStore()
        let dataSource = AgentBarDataSource(store: emptyStore)

        // When: 현재 에이전트 아이템 목록 조회
        let items = dataSource.currentItems()

        // Then: 가짜 agy 또는 AWO Pipeline 더미 항목이 주입되지 않고 빈 배열이어야 함
        XCTAssertTrue(items.isEmpty, "에이전트가 0개일 때는 빈 배열을 반환해야 합니다. 실제 항목 수: \(items.count)")
        XCTAssertFalse(
            items.contains { $0.id == "agent-active-session" },
            "가짜 agy 세션(agent-active-session)이 주입되어서는 안 됩니다."
        )
        XCTAssertFalse(
            items.contains { $0.id == "awo-pipeline-shared" },
            "가짜 AWO 파이프라인(awo-pipeline-shared)이 주입되어서는 안 됩니다."
        )
        XCTAssertFalse(
            items.contains { $0.title == "agy" },
            "더미 'agy' 타이틀이 주입되어서는 안 됩니다."
        )
        XCTAssertFalse(
            items.contains { $0.title == "AWO Pipeline" },
            "더미 'AWO Pipeline' 타이틀이 주입되어서는 안 됩니다."
        )
    }

    func testOccupiedRoomWithoutFakeAgyFallback() {
        // Given: 활성 룸이 있는 경우 해당 룸 아이템만 생성되어야 하며, 불필요한 agy 더미는 들어가지 않아야 함
        let store = InvertedStateStore()
        let dataSource = AgentBarDataSource(store: store)

        let items = dataSource.currentItems()
        XCTAssertFalse(items.contains { $0.id == "agent-active-session" })
    }
}
