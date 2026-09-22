import Foundation

/// 현재 작업 중인 방(Room) 정보 — `agent-work-todo placement list --state executing`
public struct ActiveRoomEntry: Sendable, Equatable, Identifiable, Codable {
    public let id: String
    public let planID: String
    public let title: String
    public let blueprintSlug: String
    public let occupant: String
    public let occupantHandle: String
    public let workdir: String?
    public let state: String
    public let handoverState: String
    public let tenantID: String
    public let humanGate: Bool
    public let agentBinding: RoomAgentBinding?

    public init(
        id: String,
        planID: String,
        title: String,
        blueprintSlug: String,
        occupant: String,
        occupantHandle: String,
        workdir: String?,
        state: String,
        handoverState: String,
        tenantID: String,
        humanGate: Bool = false,
        agentBinding: RoomAgentBinding? = nil
    ) {
        self.id = id
        self.planID = planID
        self.title = title
        self.blueprintSlug = blueprintSlug
        self.occupant = occupant
        self.occupantHandle = occupantHandle
        self.workdir = workdir
        self.state = state
        self.handoverState = handoverState
        self.tenantID = tenantID
        self.humanGate = humanGate
        self.agentBinding = agentBinding
    }

    public var cleanTitle: String {
        if title.hasPrefix("spawn: ") {
            return String(title.dropFirst(7))
        }
        return title
    }

    public var shortOccupant: String {
        var name = occupant
        if name.hasPrefix("agent:") {
            name = String(name.dropFirst(6))
        }
        if let atIdx = name.firstIndex(of: "@") {
            name = String(name[..<atIdx])
        }
        return name.isEmpty ? occupantHandle : name
    }

    public var isOccupied: Bool {
        state == "occupied" || state == "executing"
    }

    public var isGated: Bool {
        if humanGate { return true }
        let gatedStates: Set<String> = ["humanGate", "gated"]
        return gatedStates.contains(state) || gatedStates.contains(handoverState)
    }

    public func withAgentBinding(_ agentBinding: RoomAgentBinding?) -> ActiveRoomEntry {
        ActiveRoomEntry(
            id: id,
            planID: planID,
            title: title,
            blueprintSlug: blueprintSlug,
            occupant: occupant,
            occupantHandle: occupantHandle,
            workdir: workdir,
            state: state,
            handoverState: handoverState,
            tenantID: tenantID,
            humanGate: humanGate,
            agentBinding: agentBinding
        )
    }
}
