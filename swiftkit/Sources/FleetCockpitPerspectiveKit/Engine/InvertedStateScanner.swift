import Foundation
import os.log
import StateRootKit

enum InvertedStateScanner {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "fleetdock", category: "state-scanner")

    // MARK: - Agent 파일 탐색 및 디코딩

    static func candidateAgentFiles() -> [URL] {
        var urls: [URL] = []
        let fm = FileManager.default

        let p1 = StateRootKit.path(".swift-app-state/agent-deck.json")
        if fm.fileExists(atPath: p1) { urls.append(URL(fileURLWithPath: p1)) }

        let p2 = StateRootKit.hostPath(".swift-app-state/agent-deck.json")
        if p2 != p1 && fm.fileExists(atPath: p2) { urls.append(URL(fileURLWithPath: p2)) }

        appendTenantAgentFiles(to: &urls, fm: fm)
        return urls
    }

    private static func appendTenantAgentFiles(to urls: inout [URL], fm: FileManager) {
        let tenantsRoot = StateRootKit.hostPath(".tenants")
        guard let subdirs = try? fm.contentsOfDirectory(atPath: tenantsRoot) else { return }
        for sub in subdirs {
            let tenantPath = StateRootKit.hostPath(".tenants/\(sub)/.swift-app-state/agent-deck.json")
            if fm.fileExists(atPath: tenantPath) && !urls.contains(where: { $0.path == tenantPath }) {
                urls.append(URL(fileURLWithPath: tenantPath))
            }
        }
    }

    static func decodeAgentSessionsFromFiles(
        urls: [URL]
    ) -> (sessions: [AgentDeckStateContract.SessionEntry], latestMtime: Date) {
        var decodedSessions: [AgentDeckStateContract.SessionEntry] = []
        var maxMtime = Date.distantPast

        for url in urls {
            guard let data = try? Data(contentsOf: url) else { continue }
            do {
                let vals = try url.resourceValues(forKeys: [.contentModificationDateKey])
                if let mtime = vals.contentModificationDate, mtime > maxMtime {
                    maxMtime = mtime
                }
            } catch {
                _ = "\(error)"
            }
            do {
                let contract = try JSONDecoder().decode(AgentDeckStateContract.self, from: data)
                decodedSessions.append(contentsOf: contract.sessions)
            } catch {
                _ = "\(error)"
            }
        }
        return (decodedSessions, maxMtime)
    }

    // MARK: - 경로 및 문자열 매칭 헬퍼

    static func isPathPrefixMatch(_ pathA: String, _ pathB: String) -> Bool {
        if pathA == pathB { return true }
        return pathA.hasPrefix(pathB) || pathB.hasPrefix(pathA)
    }

    static func roomMatchesAgent(room: ActiveRoomEntry, agent: HostAgentProcess) -> Bool {
        guard let binding = room.agentBinding,
              let sessionID = agent.sessionID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !sessionID.isEmpty else {
            return false
        }
        return binding.sessionID == sessionID
    }

    static func synthesizeAgentEntries(
        from agents: [HostAgentProcess],
        activeRooms: [ActiveRoomEntry]
    ) -> [AgentSessionEntry] {
        agents.map { agent in
            let matchedRoom = activeRooms.first { room in
                roomMatchesAgent(room: room, agent: agent)
            }

            let folderFallback: String? = agent.cwd.flatMap { c in
                let last = URL(fileURLWithPath: c).lastPathComponent
                return (last.isEmpty || last == "/") ? nil : last
            }
            let projectName: String? = {
                if let title = agent.title, !title.isEmpty, title != folderFallback {
                    return title
                }
                return matchedRoom?.cleanTitle ?? folderFallback
            }()

            let mappedSubagents = agent.subagents.map { sub in
                AgentSessionEntry(
                    pid: sub.pid,
                    tool: sub.tool,
                    projectName: sub.title,
                    cwd: sub.cwd,
                    subjobCount: sub.subjobCount,
                    runningSubjobCount: sub.runningSubjobCount,
                    sessionID: sub.sessionID,
                    status: sub.status,
                    container: sub.container,
                    model: sub.model
                )
            }

            return AgentSessionEntry(
                pid: agent.pid,
                tool: agent.tool,
                projectName: projectName,
                cwd: agent.cwd,
                subjobCount: agent.subjobCount,
                runningSubjobCount: agent.runningSubjobCount,
                sessionID: agent.sessionID,
                status: agent.status,
                container: agent.container,
                model: agent.model,
                subagents: mappedSubagents
            )
        }
    }

    // MARK: - AWO 파일 탐색 및 파싱

    static func candidateAwoFiles() -> [URL] {
        var urls: [URL] = []
        let fm = FileManager.default

        let p1 = StateRootKit.path(".swift-app-state/agent-worker-orchestrator.json")
        if fm.fileExists(atPath: p1) { urls.append(URL(fileURLWithPath: p1)) }

        let p2 = StateRootKit.hostPath(".swift-app-state/agent-worker-orchestrator.json")
        if p2 != p1 && fm.fileExists(atPath: p2) { urls.append(URL(fileURLWithPath: p2)) }

        appendTenantAwoFiles(to: &urls, fm: fm)
        return urls
    }

    private static func appendTenantAwoFiles(to urls: inout [URL], fm: FileManager) {
        let tenantsRoot = StateRootKit.hostPath(".tenants")
        guard let subdirs = try? fm.contentsOfDirectory(atPath: tenantsRoot) else { return }
        for sub in subdirs {
            let tenantPath = StateRootKit.hostPath(".tenants/\(sub)/.swift-app-state/agent-worker-orchestrator.json")
            if fm.fileExists(atPath: tenantPath) && !urls.contains(where: { $0.path == tenantPath }) {
                urls.append(URL(fileURLWithPath: tenantPath))
            }
        }
    }

    struct AwoEnvelope: Decodable {
        struct JobRaw: Decodable {
            var id: String
            var title: String?
            var state: String?
            var tenantID: String?
            var workdir: String?
            var slug: String?
            var appSlug: String?
        }
        struct InnerState: Decodable {
            var jobs: [JobRaw]?
        }
        var state: InnerState?
        var jobs: [JobRaw]?
    }

    static func parseAwoData(_ data: Data) -> [AwoJobEntry] {
        guard let decoded = try? JSONDecoder().decode(AwoEnvelope.self, from: data) else {
            return []
        }
        let rawJobs = decoded.state?.jobs ?? decoded.jobs ?? []
        return rawJobs.map { raw in
            AwoJobEntry(
                id: raw.id,
                title: raw.title ?? raw.id,
                state: raw.state ?? "unknown",
                tenantID: raw.tenantID,
                workdir: raw.workdir,
                slug: raw.slug ?? raw.appSlug
            )
        }
    }

    // MARK: - Room 파일 탐색

    static func candidateRoomFiles() -> [URL] {
        let fm = FileManager.default
        let paths = [
            StateRootKit.path(".swift-app-state/agent-work-todo.json"),
            StateRootKit.hostPath(".swift-app-state/agent-work-todo.json"),
            StateRootKit.hostPath(".tenants/personal/.swift-app-state/agent-work-todo.json")
        ]
        var seen = Set<String>()
        return paths.compactMap { p in
            guard !seen.contains(p), fm.fileExists(atPath: p) else { return nil }
            seen.insert(p)
            return URL(fileURLWithPath: p)
        }
    }

    // MARK: - Room graph exact binding

    private struct RoomGraphEnvelope: Decodable {
        var rooms: [Room]?

        struct Room: Decodable {
            var id: String?
            var slug: String?
            var tenant: String?
            var parentID: String?
            var seat: Seat?
            var pane: Pane?
            var badge: String?
            var attention: String?
        }

        struct Seat: Decodable {
            var identity: String?
            var session: String?
        }

        struct Pane: Decodable {
            var paneID: String?
            var title: String?
            var focused: Bool?
        }
    }

    static func candidateRoomGraphFiles() -> [URL] {
        let fm = FileManager.default
        var paths = [
            StateRootKit.path(".swift-app-state/room-graph.json"),
            StateRootKit.hostPath(".swift-app-state/room-graph.json")
        ]

        let tenantsRoot = StateRootKit.hostPath(".tenants")
        let tenantDirectoryResult = Result { try fm.contentsOfDirectory(atPath: tenantsRoot) }
        switch tenantDirectoryResult {
        case .success(let tenants):
            paths.append(contentsOf: tenants.map {
                StateRootKit.hostPath(".tenants/\($0)/.swift-app-state/room-graph.json")
            })
        case .failure(let error):
            logger.debug("Tenant room graph discovery skipped: \(error.localizedDescription)")
        }

        var seen = Set<String>()
        return paths.compactMap { path in
            guard seen.insert(path).inserted, fm.fileExists(atPath: path) else { return nil }
            return URL(fileURLWithPath: path)
        }
    }

    static func parseRoomAgentBindings(_ data: Data) -> [RoomAgentBinding] {
        guard let envelope = try? JSONDecoder().decode(RoomGraphEnvelope.self, from: data) else {
            return []
        }
        return (envelope.rooms ?? []).compactMap { room in
            let badge = room.badge?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard badge == "full" || badge == "hookOnly",
                  let roomID = room.id,
                  !RoomAgentBinding.normalizedRoomID(roomID).isEmpty,
                  let identity = room.seat?.identity?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !identity.isEmpty,
                  let sessionID = room.seat?.session?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !sessionID.isEmpty else {
                return nil
            }
            return RoomAgentBinding(
                roomID: roomID,
                tenantID: room.tenant,
                parentRoomID: room.parentID,
                identity: identity,
                sessionID: sessionID,
                paneID: room.pane?.paneID,
                paneTitle: room.pane?.title,
                paneFocused: room.pane?.focused ?? false,
                attention: room.attention,
                roomSlug: room.slug
            )
        }
    }

    static func decodeRoomAgentBindingsFromFiles(urls: [URL]) -> [RoomAgentBinding] {
        urls.flatMap { url -> [RoomAgentBinding] in
            guard let data = try? Data(contentsOf: url) else { return [] }
            return parseRoomAgentBindings(data)
        }
    }

    static func enrichRooms(
        _ rooms: [ActiveRoomEntry],
        with candidates: [RoomAgentBinding]
    ) -> [ActiveRoomEntry] {
        let candidatesByRoomID = Dictionary(grouping: candidates, by: \.roomID)
        let enrichedRooms = rooms.map { room in
            let normalizedID = RoomAgentBinding.normalizedRoomID(room.id)
            let normalizedTenant = RoomAgentBinding.normalizedTenantID(room.tenantID)
            let exactCandidates = (candidatesByRoomID[normalizedID] ?? []).filter { candidate in
                guard !normalizedTenant.isEmpty else {
                    return candidate.tenantID.map(RoomAgentBinding.normalizedTenantID)?.isEmpty ?? true
                }
                guard let candidateTenant = candidate.tenantID else { return false }
                return RoomAgentBinding.normalizedTenantID(candidateTenant) == normalizedTenant
            }
            let binding = exactCandidates.count == 1 ? exactCandidates[0] : nil
            return room.withAgentBinding(binding)
        }
        return enrichedRooms + graphOnlyLiveRooms(
            candidates: candidates,
            candidatesByRoomID: candidatesByRoomID,
            existingRooms: rooms
        )
    }

    private static func graphOnlyLiveRooms(
        candidates: [RoomAgentBinding],
        candidatesByRoomID: [String: [RoomAgentBinding]],
        existingRooms: [ActiveRoomEntry]
    ) -> [ActiveRoomEntry] {
        let existingRoomIDs = Set(existingRooms.map { RoomAgentBinding.normalizedRoomID($0.id) })
        let allowedTenantIDs = Set(existingRooms.compactMap { room -> String? in
            let tenantID = RoomAgentBinding.normalizedTenantID(room.tenantID)
            return tenantID.isEmpty ? nil : tenantID
        })
        var emittedRoomIDs = Set<String>()

        return candidates.compactMap { binding in
            let roomID = RoomAgentBinding.normalizedRoomID(binding.roomID)
            guard !existingRoomIDs.contains(roomID),
                  emittedRoomIDs.insert(roomID).inserted,
                  candidatesByRoomID[roomID]?.count == 1,
                  let tenantID = binding.tenantID else {
                return nil
            }

            let normalizedTenantID = RoomAgentBinding.normalizedTenantID(tenantID)
            guard !normalizedTenantID.isEmpty,
                  allowedTenantIDs.contains(normalizedTenantID) else {
                return nil
            }
            let slug = binding.roomSlug ?? "agent-room"
            return ActiveRoomEntry(
                id: roomID,
                planID: binding.parentRoomID ?? "live-agent-rooms",
                title: displayTitle(for: slug),
                blueprintSlug: slug,
                occupant: binding.identity,
                occupantHandle: "",
                workdir: nil,
                state: "occupied",
                handoverState: "none",
                tenantID: normalizedTenantID,
                agentBinding: binding
            )
        }
    }

    private static func displayTitle(for slug: String) -> String {
        slug
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { word in
                word.prefix(1).uppercased() + String(word.dropFirst())
            }
            .joined(separator: " ")
    }
}
