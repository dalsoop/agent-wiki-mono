import Foundation
import InteropKit

/// 방과 AWO 잡 간의 결합 결과 모델
public struct AttributedRoomJob: Sendable, Equatable, Identifiable {
    public var id: String { "\(room.id):::\(job.id)" }
    public let room: BridgeRoomSummary
    public let job: BridgeJobSummary
    public let confidence: Double
    public let tier: AttributionTier
    public let matchedAt: Date

    public init(
        room: BridgeRoomSummary,
        job: BridgeJobSummary,
        confidence: Double,
        tier: AttributionTier,
        matchedAt: Date = Date()
    ) {
        self.room = room
        self.job = job
        self.confidence = confidence
        self.tier = tier
        self.matchedAt = matchedAt
    }
}

public enum AttributionTier: String, Sendable, Codable {
    case tier1OriginRef = "tier1_origin_ref"
    case tier2CanonicalWorkdir = "tier2_canonical_workdir"
    case tier3WorktreeContainment = "tier3_worktree_containment"
    case tier4OccupantSession = "tier4_occupant_session"
    case unassigned = "unassigned"
}

public struct BridgeRoomSummary: Sendable, Equatable, Identifiable {
    public let id: String
    public let planID: String
    public let title: String
    public let blueprintSlug: String
    public let occupant: String
    public let occupantHandle: String
    public let workdir: String?
    public let canonicalWorkdir: String?
    public let state: String
    public let tenantID: String
    public let toolbelt: [String]
    
    public init(
        id: String,
        planID: String,
        title: String,
        blueprintSlug: String,
        occupant: String,
        occupantHandle: String,
        workdir: String?,
        canonicalWorkdir: String?,
        state: String,
        tenantID: String,
        toolbelt: [String]
    ) {
        self.id = id
        self.planID = planID
        self.title = title
        self.blueprintSlug = blueprintSlug
        self.occupant = occupant
        self.occupantHandle = occupantHandle
        self.workdir = workdir
        self.canonicalWorkdir = canonicalWorkdir
        self.state = state
        self.tenantID = tenantID
        self.toolbelt = toolbelt
    }
}

public struct BridgeJobSummary: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let state: String // queued, running, verifying, succeeded, failed, stopped, blocked
    public let detailedPhase: BridgeJobPhase
    public let workdir: String
    public let canonicalWorkdir: String
    public let tenantID: String?
    public let origin: OriginRef?
    public let claimedBy: String?
    public let processID: Int32?
    public let logPath: String?
    public let since: Date
    public let progressRatio: Double?
    
    public init(
        id: String,
        title: String,
        state: String,
        detailedPhase: BridgeJobPhase,
        workdir: String,
        canonicalWorkdir: String,
        tenantID: String?,
        origin: OriginRef?,
        claimedBy: String?,
        processID: Int32?,
        logPath: String?,
        since: Date,
        progressRatio: Double?
    ) {
        self.id = id
        self.title = title
        self.state = state
        self.detailedPhase = detailedPhase
        self.workdir = workdir
        self.canonicalWorkdir = canonicalWorkdir
        self.tenantID = tenantID
        self.origin = origin
        self.claimedBy = claimedBy
        self.processID = processID
        self.logPath = logPath
        self.since = since
        self.progressRatio = progressRatio
    }
}

public enum BridgeJobPhase: String, Sendable, Codable {
    case queued
    case preparingWorktree
    case runningWorker
    case verifying
    case reconciling
    case succeeded
    case failed
    case stopped
    case blocked
}

public enum AttributionEngine {
    public static func canonicalPath(_ path: String?) -> String? {
        guard let path, !path.isEmpty else { return nil }
        let expanded = (path as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded).resolvingSymlinksInPath().standardized
        var normalized = url.path
        while normalized.count > 1 && normalized.hasSuffix("/") {
            normalized.removeLast()
        }
        return normalized
    }

    public static func isSubpath(child: String, parent: String) -> Bool {
        guard let c = canonicalPath(child), let p = canonicalPath(parent) else { return false }
        if c == p { return true }
        let parentWithSlash = p.hasSuffix("/") ? p : p + "/"
        return c.hasPrefix(parentWithSlash)
    }

    public static func attribute(
        rooms: [BridgeRoomSummary],
        jobs: [BridgeJobSummary],
        blueprints: [String: [String]]
    ) -> (attributed: [AttributedRoomJob], unassignedJobs: [BridgeJobSummary], unassignedRooms: [BridgeRoomSummary]) {
        var attributedList: [AttributedRoomJob] = []
        var remainingJobs = jobs
        var assignedRoomIDs = Set<String>()

        matchTier1(rooms: rooms, remainingJobs: &remainingJobs, assignedRoomIDs: &assignedRoomIDs, attributedList: &attributedList)
        matchTier2(rooms: rooms, remainingJobs: &remainingJobs, assignedRoomIDs: &assignedRoomIDs, attributedList: &attributedList)
        matchTier3(
            rooms: rooms,
            blueprints: blueprints,
            remainingJobs: &remainingJobs,
            assignedRoomIDs: &assignedRoomIDs,
            attributedList: &attributedList
        )
        matchTier4(rooms: rooms, remainingJobs: &remainingJobs, assignedRoomIDs: &assignedRoomIDs, attributedList: &attributedList)

        let unassignedRooms = rooms.filter { !assignedRoomIDs.contains($0.id) }
        return (attributedList, remainingJobs, unassignedRooms)
    }

    private static func matchTier1(
        rooms: [BridgeRoomSummary],
        remainingJobs: inout [BridgeJobSummary],
        assignedRoomIDs: inout Set<String>,
        attributedList: inout [AttributedRoomJob]
    ) {
        for job in remainingJobs {
            if let origin = job.origin, origin.app == "agent-work-todo" {
                if let matchedRoom = rooms.first(where: { $0.id == origin.roomID }) {
                    attributedList.append(AttributedRoomJob(room: matchedRoom, job: job, confidence: 1.0, tier: .tier1OriginRef))
                    assignedRoomIDs.insert(matchedRoom.id)
                    remainingJobs.removeAll(where: { $0.id == job.id })
                }
            }
        }
    }

    private static func matchTier2(
        rooms: [BridgeRoomSummary],
        remainingJobs: inout [BridgeJobSummary],
        assignedRoomIDs: inout Set<String>,
        attributedList: inout [AttributedRoomJob]
    ) {
        for room in rooms where !assignedRoomIDs.contains(room.id) {
            guard let rWorkdir = room.canonicalWorkdir else { continue }
            if let jobIndex = remainingJobs.firstIndex(where: { job in
                let workdirMatches = (job.canonicalWorkdir == rWorkdir)
                let tenantMatches = (job.tenantID == nil || job.tenantID == room.tenantID)
                return workdirMatches && tenantMatches
            }) {
                let matchedJob = remainingJobs.remove(at: jobIndex)
                attributedList.append(AttributedRoomJob(room: room, job: matchedJob, confidence: 0.99, tier: .tier2CanonicalWorkdir))
                assignedRoomIDs.insert(room.id)
            }
        }
    }

    private static func matchTier3(
        rooms: [BridgeRoomSummary],
        blueprints: [String: [String]],
        remainingJobs: inout [BridgeJobSummary],
        assignedRoomIDs: inout Set<String>,
        attributedList: inout [AttributedRoomJob]
    ) {
        for room in rooms where !assignedRoomIDs.contains(room.id) {
            guard let rWorkdir = room.canonicalWorkdir else { continue }
            let tools = blueprints[room.blueprintSlug] ?? room.toolbelt
            let hasAwoInToolbelt = tools.contains("agent-worker-orchestrator") || tools.contains("awo")

            if let jobIndex = remainingJobs.firstIndex(where: { job in
                let subpathMatch = isSubpath(child: job.canonicalWorkdir, parent: rWorkdir) ||
                                   isSubpath(child: rWorkdir, parent: job.canonicalWorkdir)
                return subpathMatch && hasAwoInToolbelt
            }) {
                let matchedJob = remainingJobs.remove(at: jobIndex)
                attributedList.append(AttributedRoomJob(room: room, job: matchedJob, confidence: 0.95, tier: .tier3WorktreeContainment))
                assignedRoomIDs.insert(room.id)
            }
        }
    }

    private static func matchTier4(
        rooms: [BridgeRoomSummary],
        remainingJobs: inout [BridgeJobSummary],
        assignedRoomIDs: inout Set<String>,
        attributedList: inout [AttributedRoomJob]
    ) {
        for room in rooms where !assignedRoomIDs.contains(room.id) {
            if let jobIndex = remainingJobs.firstIndex(where: { job in
                guard let claimed = job.claimedBy, !claimed.isEmpty else { return false }
                return claimed.contains(room.occupantHandle) || room.occupantHandle.contains(claimed)
            }) {
                let matchedJob = remainingJobs.remove(at: jobIndex)
                attributedList.append(AttributedRoomJob(room: room, job: matchedJob, confidence: 0.90, tier: .tier4OccupantSession))
                assignedRoomIDs.insert(room.id)
            }
        }
    }
}
