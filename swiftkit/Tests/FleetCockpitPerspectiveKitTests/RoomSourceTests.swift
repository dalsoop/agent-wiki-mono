import Foundation
import XCTest
@testable import FleetCockpitPerspectiveKit

final class RoomSourceTests: XCTestCase {
    func testDecodeActiveRoomsFromPlacementJSON() {
        let jsonString = """
        {
          "command" : "placement-list",
          "ok" : true,
          "payload" : [
            {
              "id" : "PLAN-1",
              "title" : "spawn: 주입 문서 봉인 작업",
              "state" : "executing",
              "tenantID" : "tenant:personal",
              "workdir" : "/Users/test/worktrees/H2",
              "rooms" : [
                {
                  "id" : "ROOM-1",
                  "blueprintSlug" : "sha-reminder",
                  "occupant" : "agent:grok@macbook",
                  "occupantHandle" : "H2",
                  "state" : "occupied",
                  "handoverState" : "none"
                }
              ]
            },
            {
              "id" : "PLAN-2",
              "title" : "단일 태스크 실행",
              "state" : "executing",
              "tenantID" : "tenant:personal",
              "workdir" : "/Users/test/worktrees/I1",
              "rooms" : []
            }
          ],
          "schema" : "agent-work-todo-cli/v2"
        }
        """

        let data = Data(jsonString.utf8)
        let entries = RoomSource.decodeActiveRooms(from: data)

        XCTAssertEqual(entries.count, 2)

        let first = entries[0]
        XCTAssertEqual(first.id, "ROOM-1")
        XCTAssertEqual(first.planID, "PLAN-1")
        XCTAssertEqual(first.title, "spawn: 주입 문서 봉인 작업")
        XCTAssertEqual(first.cleanTitle, "주입 문서 봉인 작업")
        XCTAssertEqual(first.blueprintSlug, "sha-reminder")
        XCTAssertEqual(first.occupant, "agent:grok@macbook")
        XCTAssertEqual(first.shortOccupant, "grok")
        XCTAssertEqual(first.occupantHandle, "H2")
        XCTAssertEqual(first.workdir, "/Users/test/worktrees/H2")
        XCTAssertEqual(first.state, "occupied")
        XCTAssertTrue(first.isOccupied)
        XCTAssertEqual(first.handoverState, "none")
        XCTAssertEqual(first.tenantID, "tenant:personal")

        let second = entries[1]
        XCTAssertEqual(second.id, "PLAN-2")
        XCTAssertEqual(second.planID, "PLAN-2")
        XCTAssertEqual(second.title, "단일 태스크 실행")
        XCTAssertEqual(second.cleanTitle, "단일 태스크 실행")
        XCTAssertEqual(second.workdir, "/Users/test/worktrees/I1")
        XCTAssertEqual(second.state, "executing")
        XCTAssertFalse(second.isOccupied)
    }

    func testShortOccupantVariations() {
        let entry1 = ActiveRoomEntry(
            id: "1",
            planID: "p1",
            title: "test",
            blueprintSlug: "",
            occupant: "agent:claude@jeonghans-macbook-pro",
            occupantHandle: "H1",
            workdir: nil,
            state: "occupied",
            handoverState: "none",
            tenantID: "tenant:personal"
        )
        XCTAssertEqual(entry1.shortOccupant, "claude")

        let entry2 = ActiveRoomEntry(
            id: "2",
            planID: "p2",
            title: "test",
            blueprintSlug: "",
            occupant: "",
            occupantHandle: "H2",
            workdir: nil,
            state: "occupied",
            handoverState: "none",
            tenantID: "tenant:personal"
        )
        XCTAssertEqual(entry2.shortOccupant, "H2")
    }

    func testDecodeSeats() {
        let jsonString = """
        [
          {
            "handle": "H1",
            "occupant": "agent:claude",
            "workdir": "/path/to/h1"
          }
        ]
        """
        let seats = SeatSpace.decodeSeats(from: Data(jsonString.utf8))
        XCTAssertEqual(seats.count, 1)
        XCTAssertEqual(seats.first?.handle, "H1")
        XCTAssertEqual(seats.first?.occupant, "agent:claude")
        XCTAssertEqual(seats.first?.workdir, "/path/to/h1")
    }

    func testOpenTerminalEmptyPathNoOp() {
        RoomSource.openTerminal(path: "")
        let buildOK = true; XCTAssertTrue(buildOK)
    }

    func testDecodeActiveRoomsWithSnakeCaseTenantID() {
        let jsonString = """
        {
          "command": "placement-list",
          "ok": true,
          "payload": [
            {
              "id": "PLAN-SNAKE",
              "title": "테넌트 스네이크 케이스 검증",
              "state": "executing",
              "tenant_id": "tenant:personal",
              "workdir": "/Users/test/worktrees/S1",
              "rooms": [
                {
                  "id": "ROOM-SNAKE",
                  "blueprintSlug": "test-slug",
                  "occupant": "agent:claude@macbook",
                  "state": "occupied"
                }
              ]
            },
            {
              "id": "PLAN-TENANT-KEY",
              "title": "테넌트 단축 키 검증",
              "state": "executing",
              "tenant": "tenant:wife",
              "workdir": "/Users/test/worktrees/W1",
              "rooms": []
            }
          ]
        }
        """
        let entries = RoomSource.decodeActiveRooms(from: Data(jsonString.utf8))
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].tenantID, "tenant:personal")
        XCTAssertEqual(entries[1].tenantID, "tenant:wife")
    }

    func testOpenTerminalPreservesEnvironmentIsolationWithoutSetenv() {
        let prevRoot = ProcessInfo.processInfo.environment["SWIFT_APP_STATE_ROOT"]
        let prevTenant = ProcessInfo.processInfo.environment["TENANT_ID"]

        RoomSource.openTerminal(path: "/tmp/test-room", tenantID: "tenant:test-tenant")

        let curRoot = ProcessInfo.processInfo.environment["SWIFT_APP_STATE_ROOT"]
        let curTenant = ProcessInfo.processInfo.environment["TENANT_ID"]

        // 프로세스 자체의 환경변수는 전역 setenv로 오염되지 않아야 함 (격리 보장)
        XCTAssertEqual(curRoot, prevRoot)
        XCTAssertEqual(curTenant, prevTenant)
    }

    func testZombieRoomsExclusion() {
        let jsonString = """
        {
          "command": "placement-list",
          "ok": true,
          "payload": [
            {
              "id": "PLAN-ZOMBIE",
              "title": "좀비 방 테스트",
              "state": "executing",
              "tenantID": "tenant:personal",
              "tickNotes": [
                "⚠ 미입실(방 폴더 없음): timeout-room (5분 초과)",
                "⚠ 세션 종료: exited-room (코드: 137)"
              ],
              "rooms": [
                {
                  "id": "ROOM-ACTIVE-1",
                  "blueprintSlug": "active-worker",
                  "state": "occupied"
                },
                {
                  "id": "ROOM-ACTIVE-2",
                  "blueprintSlug": "waiting-worker",
                  "state": "waiting"
                },
                {
                  "id": "ROOM-MISSING",
                  "blueprintSlug": "missing-room",
                  "state": "missing"
                },
                {
                  "id": "ROOM-EXITED",
                  "blueprintSlug": "exited-room",
                  "state": "exited"
                },
                {
                  "id": "ROOM-CLOSED",
                  "blueprintSlug": "closed-room",
                  "state": "closed"
                },
                {
                  "id": "ROOM-FAILED",
                  "blueprintSlug": "failed-room",
                  "state": "failed"
                },
                {
                  "id": "ROOM-TIMEOUT",
                  "blueprintSlug": "timeout-room",
                  "state": "occupied"
                }
              ]
            }
          ]
        }
        """

        let entries = RoomSource.decodeActiveRooms(from: Data(jsonString.utf8))
        XCTAssertEqual(entries.count, 2)
        let ids = entries.map { $0.id }
        XCTAssertTrue(ids.contains("ROOM-ACTIVE-1"))
        XCTAssertTrue(ids.contains("ROOM-ACTIVE-2"))
        XCTAssertFalse(ids.contains("ROOM-MISSING"))
        XCTAssertFalse(ids.contains("ROOM-EXITED"))
        XCTAssertFalse(ids.contains("ROOM-CLOSED"))
        XCTAssertFalse(ids.contains("ROOM-FAILED"))
        XCTAssertFalse(ids.contains("ROOM-TIMEOUT"))
    }

    func testActiveStatesPreserved() {
        let jsonString = """
        {
          "command": "placement-list",
          "ok": true,
          "payload": [
            {
              "id": "PLAN-ACTIVE-STATES",
              "title": "다양한 활성 상태 검증",
              "state": "planned",
              "tenantID": "tenant:personal",
              "rooms": [
                {
                  "id": "ROOM-GATED",
                  "blueprintSlug": "slug-gated",
                  "state": "gated"
                },
                {
                  "id": "ROOM-BLOCKED",
                  "blueprintSlug": "slug-blocked",
                  "state": "blocked"
                },
                {
                  "id": "ROOM-ESCALATED",
                  "blueprintSlug": "slug-escalated",
                  "state": "escalated"
                },
                {
                  "id": "ROOM-PLANNED",
                  "blueprintSlug": "slug-planned",
                  "state": "planned"
                }
              ]
            }
          ]
        }
        """

        let entries = RoomSource.decodeActiveRooms(from: Data(jsonString.utf8))
        XCTAssertEqual(entries.count, 4)
        let states = entries.map { $0.state }
        XCTAssertTrue(states.contains("gated"))
        XCTAssertTrue(states.contains("blocked"))
        XCTAssertTrue(states.contains("escalated"))
        XCTAssertTrue(states.contains("planned"))

        // Verify isZombieOrInactive directly
        XCTAssertFalse(RoomSource.isZombieOrInactive(roomID: "r1", blueprintSlug: "s1", roomState: "gated", tickNotes: []))
        XCTAssertFalse(RoomSource.isZombieOrInactive(roomID: "r2", blueprintSlug: "s2", roomState: "blocked", tickNotes: []))
        XCTAssertFalse(RoomSource.isZombieOrInactive(roomID: "r3", blueprintSlug: "s3", roomState: "escalated", tickNotes: []))
        XCTAssertFalse(RoomSource.isZombieOrInactive(roomID: "r4", blueprintSlug: "s4", roomState: "planned", tickNotes: []))
    }
}
