import Foundation
import XCTest
@testable import FleetCockpitPerspectiveKit

final class RoomLeaseSourceTests: XCTestCase {
    func testDecodeBlueprints() {
        let jsonString = """
        {
          "command": "room-list",
          "ok": true,
          "payload": [
            {
              "slug": "wiring-room",
              "title": "실배선실",
              "toolbelt": ["agent-work-todo", "agent-worker-orchestrator"]
            },
            {
              "slug": "sha-system",
              "title": "SHA",
              "toolbelt": []
            }
          ]
        }
        """

        let blueprints = RoomLeaseSource.decodeBlueprints(from: Data(jsonString.utf8))
        XCTAssertEqual(blueprints.count, 2)
        XCTAssertEqual(blueprints["wiring-room"], ["agent-work-todo", "agent-worker-orchestrator"])
        XCTAssertEqual(blueprints["sha-system"], [])
    }

    func testBuildSnapshotMatrix() {
        let room1 = ActiveRoomEntry(
            id: "R1",
            planID: "P1",
            title: "spawn: 실배선 정비",
            blueprintSlug: "wiring-room",
            occupant: "agent:grok@macbook",
            occupantHandle: "H2",
            workdir: "/tmp/h2",
            state: "occupied",
            handoverState: "none",
            tenantID: "tenant:personal"
        )
        let room2 = ActiveRoomEntry(
            id: "R2",
            planID: "P2",
            title: "spawn: 관제 검수",
            blueprintSlug: "wiring-room",
            occupant: "agent:claude@macbook",
            occupantHandle: "H3",
            workdir: "/tmp/h3",
            state: "occupied",
            handoverState: "simulating",
            tenantID: "tenant:personal"
        )

        let blueprints = [
            "wiring-room": ["agent-work-todo"]
        ]

        let snapshot = RoomLeaseSource.buildSnapshot(rooms: [room1, room2], blueprints: blueprints)

        XCTAssertEqual(snapshot.totalActiveRooms, 2)
        XCTAssertEqual(snapshot.totalActiveAgents, 2)
        XCTAssertEqual(snapshot.totalActiveApps, 1)

        let todoRooms = snapshot.appLeases["agent-work-todo"]
        XCTAssertEqual(todoRooms?.count, 2)

        let grokRooms = snapshot.agentRooms["grok"]
        XCTAssertEqual(grokRooms?.count, 1)
        XCTAssertEqual(grokRooms?.first?.id, "R1")

        let claudeRooms = snapshot.agentRooms["claude"]
        XCTAssertEqual(claudeRooms?.count, 1)
        XCTAssertEqual(claudeRooms?.first?.id, "R2")
    }

    func testSnapshotInvariantValidation() {
        let validRoom = ActiveRoomEntry(
            id: "R1",
            planID: "P1",
            title: "방 1",
            blueprintSlug: "slug1",
            occupant: "agent:grok@macbook",
            occupantHandle: "H1",
            workdir: "/tmp",
            state: "occupied",
            handoverState: "none",
            tenantID: "tenant:personal"
        )
        let validSnapshot = FleetMatrixSnapshot(
            rooms: [validRoom],
            appLeases: ["app1": [validRoom]],
            agentRooms: ["grok": [validRoom]],
            tenantRooms: ["tenant:personal": [validRoom]]
        )
        XCTAssertTrue(validSnapshot.isValid)

        // 불변식 위반 1: rooms에 없는 외래 room이 appLeases에 포함됨
        let ghostRoom = ActiveRoomEntry(
            id: "R_GHOST",
            planID: "P_GHOST",
            title: "유령 방",
            blueprintSlug: "ghost",
            occupant: "ghost",
            occupantHandle: "HG",
            workdir: nil,
            state: "occupied",
            handoverState: "none",
            tenantID: "tenant:personal"
        )
        let invalidReferentialSnapshot = FleetMatrixSnapshot(
            rooms: [validRoom],
            appLeases: ["app1": [ghostRoom]],
            agentRooms: [:],
            tenantRooms: [:]
        )
        XCTAssertFalse(invalidReferentialSnapshot.isValid)

        // 불변식 위반 2: rooms 내 중복 ID
        let duplicateRoom = ActiveRoomEntry(
            id: "R1", // 중복 ID
            planID: "P2",
            title: "방 1 중복",
            blueprintSlug: "slug1",
            occupant: "agent:claude@macbook",
            occupantHandle: "H2",
            workdir: "/tmp2",
            state: "occupied",
            handoverState: "none",
            tenantID: "tenant:personal"
        )
        let invalidDuplicateSnapshot = FleetMatrixSnapshot(
            rooms: [validRoom, duplicateRoom],
            appLeases: [:],
            agentRooms: [:],
            tenantRooms: [:]
        )
        XCTAssertFalse(invalidDuplicateSnapshot.isValid)

        // setCachedMatrix가 무결성 위반 스냅샷을 거절하는지 확인
        RoomLeaseSource.clearCachedMatrix()
        let rejected = RoomLeaseSource.setCachedMatrix(invalidReferentialSnapshot)
        XCTAssertFalse(rejected)
        XCTAssertFalse(RoomLeaseSource.hasValidCache)

        let accepted = RoomLeaseSource.setCachedMatrix(validSnapshot)
        XCTAssertTrue(accepted)
        XCTAssertTrue(RoomLeaseSource.hasValidCache)
        XCTAssertEqual(RoomLeaseSource.cachedMatrix().totalActiveRooms, 1)
    }

    func testAtomicCacheUpdateAndClear() {
        RoomLeaseSource.clearCachedMatrix()
        XCTAssertFalse(RoomLeaseSource.hasValidCache)
        XCTAssertEqual(RoomLeaseSource.cachedMatrix().totalActiveRooms, 0)

        let room = ActiveRoomEntry(
            id: "R100",
            planID: "P100",
            title: "테스트 방",
            blueprintSlug: "test",
            occupant: "agent:tester@macbook",
            occupantHandle: "HT",
            workdir: nil,
            state: "occupied",
            handoverState: "none",
            tenantID: "tenant:personal"
        )
        let initial = FleetMatrixSnapshot(rooms: [room])
        XCTAssertTrue(RoomLeaseSource.setCachedMatrix(initial))
        XCTAssertTrue(RoomLeaseSource.hasValidCache)

        // 원자적 갱신 (updateCachedMatrix)
        let updated = RoomLeaseSource.updateCachedMatrix { current in
            var updatedRooms = current.rooms
            let room2 = ActiveRoomEntry(
                id: "R200",
                planID: "P200",
                title: "테스트 방 2",
                blueprintSlug: "test",
                occupant: "agent:tester2@macbook",
                occupantHandle: "HT2",
                workdir: nil,
                state: "occupied",
                handoverState: "none",
                tenantID: "tenant:personal"
            )
            updatedRooms.append(room2)
            return FleetMatrixSnapshot(rooms: updatedRooms)
        }
        XCTAssertTrue(updated)
        XCTAssertEqual(RoomLeaseSource.cachedMatrix().totalActiveRooms, 2)

        // 캐시 초기화
        RoomLeaseSource.clearCachedMatrix()
        XCTAssertFalse(RoomLeaseSource.hasValidCache)
        XCTAssertEqual(RoomLeaseSource.cachedMatrix().totalActiveRooms, 0)
    }

    func testAtomicCacheAccessAndConcurrency() async {
        RoomLeaseSource.clearCachedMatrix()

        // 100개의 동시 비동기 태스크에서 캐시 읽기/쓰기/갱신을 반복하여 Data Race가 발생하지 않음을 증명
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<100 {
                group.addTask {
                    let room = ActiveRoomEntry(
                        id: "CR_\(i)",
                        planID: "CP_\(i)",
                        title: "동시성 방 \(i)",
                        blueprintSlug: "concurrent",
                        occupant: "agent:worker\(i)@macbook",
                        occupantHandle: "W\(i)",
                        workdir: nil,
                        state: "occupied",
                        handoverState: "none",
                        tenantID: "tenant:personal"
                    )
                    let snap = FleetMatrixSnapshot(rooms: [room])
                    if i % 3 == 0 {
                        RoomLeaseSource.setCachedMatrix(snap)
                    } else if i % 3 == 1 {
                        _ = RoomLeaseSource.cachedMatrix()
                    } else {
                        RoomLeaseSource.updateCachedMatrix { _ in snap }
                    }
                }
            }
        }

        // 모든 동시성 작업 완료 후 캐시는 유효한 상태여야 함
        XCTAssertTrue(RoomLeaseSource.hasValidCache)
        let finalSnapshot = RoomLeaseSource.cachedMatrix()
        XCTAssertTrue(finalSnapshot.isValid)
    }

    func testBuildSnapshotDeduplication() {
        let roomDuplicate1 = ActiveRoomEntry(
            id: "DUP_R1",
            planID: "P1",
            title: "중복 방 1-1",
            blueprintSlug: "wiring",
            occupant: "agent:dup1@macbook",
            occupantHandle: "D1",
            workdir: nil,
            state: "occupied",
            handoverState: "none",
            tenantID: "tenant:personal"
        )
        let roomDuplicate2 = ActiveRoomEntry(
            id: "DUP_R1", // 동일 ID
            planID: "P2",
            title: "중복 방 1-2",
            blueprintSlug: "wiring",
            occupant: "agent:dup2@macbook",
            occupantHandle: "D2",
            workdir: nil,
            state: "occupied",
            handoverState: "none",
            tenantID: "tenant:personal"
        )

        let snapshot = RoomLeaseSource.buildSnapshot(
            rooms: [roomDuplicate1, roomDuplicate2],
            blueprints: ["wiring": ["agent-work-todo"]]
        )

        // 고유 ID 불변식에 따라 중복이 제거되어 1개만 남아야 함
        XCTAssertEqual(snapshot.totalActiveRooms, 1)
        XCTAssertTrue(snapshot.isValid)
    }
}
