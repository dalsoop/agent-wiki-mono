import Foundation
import XCTest
@testable import FleetCockpitPerspectiveKit

final class RoomAgentBindingProjectionTests: XCTestCase {
    func testExactRoomIDAndTenantJoinBinding() {
        let room = makeRoom(id: " 4A6F8C7D-1234-5678-9ABC-DEF012345678 ")
        let data = roomGraphData(rooms: [
            """
            {
              "id": "4a6f8c7d-1234-5678-9abc-def012345678",
              "tenant": "personal",
              "parentID": "parent-room",
              "badge": "full",
              "attention": "ok",
              "seat": {
                "identity": "agent:codex@macbook",
                "session": "session-exact"
              },
              "pane": {
                "paneID": "w6:p42",
                "title": "Codex exact pane",
                "focused": true
              }
            }
            """
        ])

        let enriched = InvertedStateScanner.enrichRooms(
            [room],
            with: InvertedStateScanner.parseRoomAgentBindings(data)
        )

        let binding = enriched[0].agentBinding
        XCTAssertEqual(binding?.roomID, "4a6f8c7d-1234-5678-9abc-def012345678")
        XCTAssertEqual(binding?.tenantID, "personal")
        XCTAssertEqual(binding?.parentRoomID, "parent-room")
        XCTAssertEqual(binding?.identity, "agent:codex@macbook")
        XCTAssertEqual(binding?.sessionID, "session-exact")
        XCTAssertEqual(binding?.paneID, "w6:p42")
        XCTAssertEqual(binding?.paneFocused, true)
        XCTAssertEqual(binding?.attention, "ok")
    }

    func testWorkdirTitleOccupantAndPrefixDoNotJoin() {
        let room = makeRoom(
            id: "room-alpha",
            title: "Same pane title",
            occupant: "agent:codex@macbook",
            workdir: "/workspace/same"
        )
        let data = roomGraphData(rooms: [
            """
            {
              "id": "room-alpha-child",
              "tenant": "tenant:personal",
              "badge": "full",
              "seat": {
                "identity": "agent:codex@macbook",
                "session": "session-other-room"
              },
              "pane": {
                "paneID": "w6:p7",
                "title": "Same pane title",
                "focused": false
              }
            }
            """
        ])

        let enriched = InvertedStateScanner.enrichRooms(
            [room],
            with: InvertedStateScanner.parseRoomAgentBindings(data)
        )
        XCTAssertNil(enriched[0].agentBinding)

        let process = HostAgentProcess(
            pid: 101,
            ppid: 1,
            tty: nil,
            tool: "codex",
            command: "codex",
            cwd: "/workspace/same",
            sessionID: "session-other-room",
            title: "Same pane title"
        )
        XCTAssertFalse(InvertedStateScanner.roomMatchesAgent(room: room, agent: process))
    }

    func testReleasedMissingWrongTenantAndAmbiguousRowsRemainUnbound() throws {
        let released = makeRoom(id: "released-room", occupant: "agent:stale@macbook")
        let missing = makeRoom(id: "missing-room")
        let wrongTenant = makeRoom(id: "tenant-room")
        let ambiguous = makeRoom(id: "ambiguous-room")
        let data = roomGraphData(rooms: [
            """
            {
              "id": "released-room",
              "tenant": "tenant:personal",
              "badge": "outside",
              "seat": { "identity": "agent:stale@macbook", "session": "stale-session" }
            }
            """,
            #"{ "id": "missing-room", "badge": "full" }"#,
            """
            {
              "id": "tenant-room",
              "tenant": "tenant:other",
              "badge": "full",
              "seat": { "identity": "agent:other@macbook", "session": "other-session" }
            }
            """,
            """
            {
              "id": "ambiguous-room",
              "tenant": "tenant:personal",
              "badge": "full",
              "seat": { "identity": "agent:first@macbook", "session": "session-1" }
            }
            """,
            """
            {
              "id": "AMBIGUOUS-ROOM",
              "tenant": "personal",
              "badge": "hookOnly",
              "seat": { "identity": "agent:second@macbook", "session": "session-2" }
            }
            """
        ])

        let enriched = InvertedStateScanner.enrichRooms(
            [released, missing, wrongTenant, ambiguous],
            with: InvertedStateScanner.parseRoomAgentBindings(data)
        )
        XCTAssertTrue(enriched.allSatisfy { $0.agentBinding == nil })

        let legacyRoomJSON = """
        {
          "id": "legacy",
          "planID": "plan",
          "title": "Legacy room",
          "blueprintSlug": "legacy",
          "occupant": "",
          "occupantHandle": "",
          "workdir": null,
          "state": "waiting",
          "handoverState": "none",
          "tenantID": "tenant:personal",
          "humanGate": false
        }
        """
        let decoded = try JSONDecoder().decode(
            ActiveRoomEntry.self,
            from: Data(legacyRoomJSON.utf8)
        )
        XCTAssertNil(decoded.agentBinding)
    }

    func testExactSessionBindingAssociatesAgent() {
        let binding = RoomAgentBinding(
            roomID: "bound-room",
            tenantID: "tenant:personal",
            parentRoomID: nil,
            identity: "agent:codex@macbook",
            sessionID: "session-bound",
            paneID: nil,
            paneTitle: nil,
            paneFocused: false
        )
        let room = makeRoom(id: "bound-room", agentBinding: binding)
        let process = HostAgentProcess(
            pid: 102,
            ppid: 1,
            tty: nil,
            tool: "codex",
            command: "codex --resume session-bound",
            cwd: "/unrelated",
            sessionID: "session-bound",
            title: "Unrelated"
        )

        XCTAssertTrue(InvertedStateScanner.roomMatchesAgent(room: room, agent: process))
    }

    func testLiveGraphOnlyCommandRoomIsProjectedAsVisibleRoom() throws {
        let data = roomGraphData(rooms: [
            """
            {
              "id": "command-room-id",
              "slug": "command-room",
              "tenant": "tenant:personal",
              "parentID": "",
              "badge": "hookOnly",
              "attention": "ok",
              "seat": {
                "identity": "agent:codex@macbook",
                "session": "session-command"
              },
              "pane": {
                "paneID": "w6:p35",
                "title": "leader-1",
                "focused": true
              }
            }
            """
        ])

        let projected = InvertedStateScanner.enrichRooms(
            [makeRoom(id: "existing-worker-room")],
            with: InvertedStateScanner.parseRoomAgentBindings(data)
        )

        XCTAssertEqual(projected.count, 2)
        let commandRoom = try XCTUnwrap(projected.first { $0.id == "command-room-id" })
        XCTAssertEqual(commandRoom.title, "Command Room")
        XCTAssertEqual(commandRoom.blueprintSlug, "command-room")
        XCTAssertEqual(commandRoom.state, "occupied")
        XCTAssertEqual(commandRoom.tenantID, "tenant:personal")
        XCTAssertEqual(commandRoom.agentBinding?.identity, "agent:codex@macbook")
        XCTAssertEqual(commandRoom.agentBinding?.paneID, "w6:p35")
    }

    func testGraphOnlyRoomFromAnotherTenantIsNotProjected() {
        let data = roomGraphData(rooms: [
            """
            {
              "id": "other-tenant-command-room",
              "slug": "command-room",
              "tenant": "tenant:other",
              "badge": "full",
              "seat": {
                "identity": "agent:other@macbook",
                "session": "other-session"
              },
              "pane": { "paneID": "w9:p9" }
            }
            """
        ])

        let projected = InvertedStateScanner.enrichRooms(
            [makeRoom(id: "personal-worker-room")],
            with: InvertedStateScanner.parseRoomAgentBindings(data)
        )

        XCTAssertEqual(projected.map(\.id), ["personal-worker-room"])
    }

    private func makeRoom(
        id: String,
        title: String = "Room",
        occupant: String = "",
        workdir: String? = nil,
        agentBinding: RoomAgentBinding? = nil
    ) -> ActiveRoomEntry {
        ActiveRoomEntry(
            id: id,
            planID: "plan",
            title: title,
            blueprintSlug: "blueprint",
            occupant: occupant,
            occupantHandle: "",
            workdir: workdir,
            state: "occupied",
            handoverState: "none",
            tenantID: "tenant:personal",
            agentBinding: agentBinding
        )
    }

    private func roomGraphData(rooms: [String]) -> Data {
        let json = """
        {
          "generatedAt": "2026-09-19T00:00:00Z",
          "rooms": [\(rooms.joined(separator: ","))]
        }
        """
        return Data(json.utf8)
    }
}
