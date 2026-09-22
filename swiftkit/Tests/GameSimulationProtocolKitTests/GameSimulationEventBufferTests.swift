import XCTest
@testable import GameSimulationProtocolKit

final class GameSimulationEventBufferTests: XCTestCase {
    func testRoutineEventsWithSameKeyCoalesceButUrgentEventsDoNot() {
        var buffer = GameSimulationEventBuffer<String>(capacity: 4)
        buffer.append(.init(
            id: "1", revision: 1, channel: .world,
            urgency: .routine, coalescingKey: "unit:a", payload: "old"
        ))
        buffer.append(.init(
            id: "2", revision: 2, channel: .world,
            urgency: .routine, coalescingKey: "unit:a", payload: "new"
        ))
        buffer.append(.init(
            id: "3", revision: 3, channel: .direct,
            urgency: .urgent, coalescingKey: "unit:a", payload: "danger"
        ))

        XCTAssertEqual(buffer.events.map(\.payload), ["new", "danger"])
    }

    func testCapacityDropsOldestNonUrgentFirst() {
        var buffer = GameSimulationEventBuffer<String>(capacity: 3)
        buffer.append(.init(id: "urgent", revision: 1, channel: .direct, urgency: .urgent, payload: "urgent"))
        buffer.append(.init(id: "noise", revision: 2, channel: .world, urgency: .noise, payload: "noise"))
        buffer.append(.init(id: "routine", revision: 3, channel: .world, urgency: .routine, payload: "routine"))
        buffer.append(.init(id: "new", revision: 4, channel: .world, urgency: .routine, payload: "new"))

        XCTAssertEqual(buffer.events.map(\.id), ["urgent", "routine", "new"])
    }

    func testZeroCapacityStoresNothing() {
        var buffer = GameSimulationEventBuffer<String>(capacity: 0)
        buffer.append(.init(id: "1", revision: 1, channel: .world, urgency: .urgent, payload: "ignored"))
        XCTAssertTrue(buffer.events.isEmpty)
    }
}
