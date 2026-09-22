import XCTest
@testable import GameRealtimeSimulationKit

final class SystemScheduleTests: XCTestCase {
    func testStableStageOrder() throws {
        let shuffled = [
            SystemSchedule.Entry(
                identifier: 40,
                stage: .cleanup,
                systemOrder: 0
            ),
            SystemSchedule.Entry(
                identifier: 21,
                stage: .collision,
                systemOrder: 7
            ),
            SystemSchedule.Entry(
                identifier: 10,
                stage: .input,
                systemOrder: 2
            ),
            SystemSchedule.Entry(
                identifier: 20,
                stage: .collision,
                systemOrder: 1
            ),
        ]

        let forward = try SystemSchedule(entries: shuffled)
        let reverse = try SystemSchedule(entries: shuffled.reversed())

        XCTAssertEqual(
            forward.orderedEntries.map(\.identifier),
            [10, 20, 21, 40]
        )
        XCTAssertEqual(reverse.orderedEntries, forward.orderedEntries)
        XCTAssertEqual(
            forward.commandKey(
                forSystemIdentifier: 21,
                sequence: 8
            ),
            CommandKey(
                stage: SystemStage.collision.rawValue,
                systemOrder: 7,
                sequence: 8
            )
        )
    }

    func testDuplicateStageOrderAndIdentifierAreRejected() throws {
        let entry = SystemSchedule.Entry(
            identifier: 10,
            stage: .simulation,
            systemOrder: 3
        )

        XCTAssertThrowsError(
            try SystemSchedule(
                entries: [
                    entry,
                    SystemSchedule.Entry(
                        identifier: 11,
                        stage: .simulation,
                        systemOrder: 3
                    ),
                ]
            )
        ) { error in
            XCTAssertEqual(
                error as? SystemScheduleError,
                .duplicateStageOrder(stage: .simulation, systemOrder: 3)
            )
        }

        XCTAssertThrowsError(
            try SystemSchedule(
                entries: [
                    entry,
                    SystemSchedule.Entry(
                        identifier: 10,
                        stage: .cleanup,
                        systemOrder: 0
                    ),
                ]
            )
        ) { error in
            XCTAssertEqual(
                error as? SystemScheduleError,
                .duplicateIdentifier(10)
            )
        }
    }

    func testStandardScheduleFixesAllStages() {
        XCTAssertEqual(
            SystemSchedule.standardV1.orderedEntries.map(\.stage),
            [.input, .simulation, .collision, .cleanup]
        )
        XCTAssertEqual(
            SystemSchedule.standardV1.orderedEntries.map(\.systemOrder),
            [0, 0, 0, 0]
        )
    }
}
