import XCTest
@testable import FleetCockpitPerspectiveKit

final class AttributionEngineTests: XCTestCase {
    func testTier0RoomIDMatch() {
        let engine = AttributionEngine()
        XCTAssertEqual(engine.attribute(jobRoomID: "test-room-id", workdir: "/some/path"), "test-room-id")
    }

    func testFallbackToSlugHeuristic() {
        let engine = AttributionEngine()
        XCTAssertEqual(engine.attribute(jobRoomID: nil, workdir: "/path/to/rooms/my-slug/work"), "my-slug")
    }

    func testFallbackFails() {
        let engine = AttributionEngine()
        XCTAssertNil(engine.attribute(jobRoomID: nil, workdir: "/just/some/path"))
    }

    func testAttributionByTier0RoomID() {
        let room = ActiveRoomEntry(
            id: "room-explicit-42",
            planID: "plan-42",
            title: "Task 42",
            blueprintSlug: "other-slug",
            occupant: "agent:claude",
            occupantHandle: "claude",
            workdir: "/different/path",
            state: "occupied",
            handoverState: "none",
            tenantID: "tenant:1"
        )
        let job = AwoJobEntry(
            id: "job-explicit",
            title: "Arbitrary Title",
            state: "running",
            workdir: "/random/workdir",
            slug: "no-match-slug",
            roomID: "room-explicit-42"
        )

        let items = AttributionEngine.attribute(rooms: [room], awoJobs: [job])
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].id, "room-room-explicit-42")
        XCTAssertEqual(items[0].subjobCount, 1)
        XCTAssertEqual(items[0].runningSubjobCount, 1)
    }

    func testAttributionByWorkdir() {
        let workdir = "/Users/tester/work/my-project"
        let room = ActiveRoomEntry(
            id: "room-1",
            planID: "plan-1",
            title: "spawn: Task A",
            blueprintSlug: "task-a",
            occupant: "agent:claude@macbook",
            occupantHandle: "claude",
            workdir: workdir,
            state: "occupied",
            handoverState: "none",
            tenantID: "tenant:personal"
        )

        let job1 = AwoJobEntry(
            id: "job-1",
            title: "Build Step 1",
            state: "running",
            workdir: workdir
        )
        let job2 = AwoJobEntry(
            id: "job-2",
            title: "Test Step 2",
            state: "queued",
            workdir: workdir
        )

        let items = AttributionEngine.attribute(rooms: [room], awoJobs: [job1, job2])
        XCTAssertEqual(items.count, 1)

        let item = items[0]
        XCTAssertEqual(item.id, "room-room-1")
        XCTAssertEqual(item.title, "Task A")
        XCTAssertEqual(item.subjobCount, 2)
        XCTAssertEqual(item.runningSubjobCount, 1)
        XCTAssertEqual(item.statusDot, .running)
        XCTAssertEqual(item.subjobString, "↳ 2 (1 run)")
    }

    func testAttributionByBlueprintSlugAndUnassignedSharedJobs() {
        let room = ActiveRoomEntry(
            id: "room-gujo",
            planID: "plan-gujo",
            title: "Gujo v3 Payment Core",
            blueprintSlug: "gujo-v3",
            occupant: "agent:agy@macbook",
            occupantHandle: "agy",
            workdir: "/path/to/gujo",
            state: "occupied",
            handoverState: "none",
            tenantID: "tenant:gujo"
        )

        let jobMatched = AwoJobEntry(
            id: "job-matched",
            title: "gujo-v3 · Pass Checkout",
            state: "running"
        )
        let jobUnassigned = AwoJobEntry(
            id: "job-unassigned",
            title: "Other Global Task",
            state: "queued"
        )

        let items = AttributionEngine.attribute(rooms: [room], awoJobs: [jobMatched, jobUnassigned])
        XCTAssertEqual(items.count, 2)

        let roomItem = items[0]
        XCTAssertEqual(roomItem.id, "room-room-gujo")
        XCTAssertEqual(roomItem.subjobCount, 1)
        XCTAssertEqual(roomItem.runningSubjobCount, 1)

        let sharedItem = items[1]
        XCTAssertEqual(sharedItem.id, "awo-shared")
        XCTAssertEqual(sharedItem.subjobCount, 1)
        XCTAssertEqual(sharedItem.runningSubjobCount, 0)
        XCTAssertEqual(sharedItem.subjobString, "↳ 1")
    }
}
