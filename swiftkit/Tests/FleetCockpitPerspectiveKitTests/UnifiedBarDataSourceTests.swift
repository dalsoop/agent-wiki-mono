import XCTest
@testable import FleetCockpitPerspectiveKit

final class UnifiedBarDataSourceTests: XCTestCase {
    func testDataSourcesConcurrentActivation() async {
        let store = InvertedStateStore.shared
        let agentDS = AgentBarDataSource(store: store)
        let roomDS = RoomBarDataSource(store: store)
        let appDS = AppBarDataSource()
        
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await agentDS.activate() }
            group.addTask { await roomDS.activate() }
            group.addTask { await appDS.activate() }
        }
        
        let agents = agentDS.currentItems()
        let rooms = roomDS.currentItems()
        let apps = appDS.currentItems()
        
        // `currentItems()` 는 옵셔널이 아니다 — NotNil 은 항상 참이라 아무것도 안 잰다.
        // 동시 활성화가 깨지는 자리는 **항목 중복**이다(같은 스토어를 세 소스가 동시에 읽는다).
        for (label, items) in [("agent", agents), ("room", rooms), ("app", apps)] {
            XCTAssertEqual(
                Set(items.map(\.id)).count, items.count,
                "\(label) 소스가 동시 활성화에서 항목을 중복시켰다: \(items.map(\.id))")
        }
        // 방은 없을 수 있지만(호스트 상태), 에이전트·앱 소스는 폴백이 있어 비면 안 된다 —
        // 비어 있으면 위 유일성 검사가 공허참이 된다.
        XCTAssertFalse(agents.isEmpty, "agent 소스가 활성화 뒤에도 빈 목록이다")
        XCTAssertFalse(apps.isEmpty, "app 소스가 활성화 뒤에도 빈 목록이다")
        XCTAssertEqual(agentDS.currentItems(), agents, "재조회가 같은 스냅숏을 줘야 한다")
        
        agentDS.deactivate()
        roomDS.deactivate()
        appDS.deactivate()
    }
}
