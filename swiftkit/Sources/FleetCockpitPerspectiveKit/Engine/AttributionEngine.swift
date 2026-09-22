import Foundation

/// AWO 잡 데이터 모델 (독 바 귀속용)
public struct AwoJobEntry: Sendable, Equatable, Identifiable, Codable {
    public let id: String
    public let title: String
    public let state: String
    public let tenantID: String?
    public let workdir: String?
    public let slug: String?
    public let roomID: String?

    public init(
        id: String,
        title: String,
        state: String,
        tenantID: String? = nil,
        workdir: String? = nil,
        slug: String? = nil,
        roomID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.state = state
        self.tenantID = tenantID
        self.workdir = workdir
        self.slug = slug
        self.roomID = roomID
    }

    public var isRunning: Bool {
        state.lowercased() == "running"
    }

    public var isQueued: Bool {
        let s = state.lowercased()
        return s == "queued" || s == "pending"
    }
}

/// 방(Room)과 AWO 잡 간의 결정론적 귀속 및 UnifiedBarItem 합성 엔진
public struct AttributionEngine: Sendable {
    public init() {}

    /// `jobRoomID`가 존재할 때 즉시 일치시키는 Tier 0 귀속 룰 (단건 헬퍼)
    public func attribute(jobRoomID: String?, workdir: String) -> String? {
        if let roomID = jobRoomID, !roomID.isEmpty {
            return roomID
        }
        let components = workdir.split(separator: "/")
        if let roomsIndex = components.lastIndex(of: "rooms"), roomsIndex + 1 < components.count {
            return String(components[roomsIndex + 1])
        }
        return nil
    }

    public static func attribute(
        rooms: [ActiveRoomEntry],
        awoJobs: [AwoJobEntry]
    ) -> [UnifiedBarItem] {
        var unassignedJobs = awoJobs
        var items: [UnifiedBarItem] = []

        for room in rooms {
            let matchedJobs = unassignedJobs.filter { job in
                // Tier 0: 결정론적 roomID 일치
                if let jRoomID = job.roomID, !jRoomID.isEmpty, jRoomID == room.id {
                    return true
                }
                if let rWorkdir = room.workdir, let jWorkdir = job.workdir, !rWorkdir.isEmpty, rWorkdir == jWorkdir {
                    return true
                }
                if let jSlug = job.slug, !jSlug.isEmpty, jSlug == room.blueprintSlug {
                    return true
                }
                if let rWorkdir = room.workdir, !rWorkdir.isEmpty, job.title.contains(rWorkdir) {
                    return true
                }
                if !room.blueprintSlug.isEmpty, job.title.localizedCaseInsensitiveContains(room.blueprintSlug) {
                    return true
                }
                return false
            }

            let matchedIds = Set(matchedJobs.map(\.id))
            unassignedJobs.removeAll { matchedIds.contains($0.id) }

            let runningCount = matchedJobs.filter { $0.isRunning }.count
            let status: BarStatusDot = room.isOccupied ? .running : .waiting

            items.append(UnifiedBarItem(
                id: "room-\(room.id)",
                title: room.cleanTitle,
                subtitle: room.shortOccupant.isEmpty ? nil : room.shortOccupant,
                icon: .symbol("person.2.badge.gearshape.fill"),
                statusDot: status,
                badge: room.handoverState == "failed" ? BarBadge(text: "ERR", kind: .attention) : nil,
                subjobCount: matchedJobs.count,
                runningSubjobCount: runningCount,
                workdir: room.workdir
            ))
        }

        if !unassignedJobs.isEmpty {
            let running = unassignedJobs.filter { $0.isRunning }.count
            items.append(UnifiedBarItem(
                id: "awo-shared",
                title: "AWO Pipeline",
                subtitle: "\(unassignedJobs.count) jobs",
                icon: .symbol("bolt.badge.automatic.fill"),
                statusDot: running > 0 ? .running : .idle,
                badge: nil,
                subjobCount: unassignedJobs.count,
                runningSubjobCount: running,
                workdir: nil
            ))
        }

        return items
    }
}
