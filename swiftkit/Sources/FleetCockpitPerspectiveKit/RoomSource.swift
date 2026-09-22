import Foundation
import InteropKit
import CommandKit
import StateRootKit
@_exported import FleetPerspectiveModelKit
import os

public struct RoomLifecycleCleanupIssue: Sendable, Equatable, Identifiable {
    public let planID: String
    public let title: String
    public let workdir: String
    public let reason: String

    public var id: String { planID }

    public init(planID: String, title: String, workdir: String, reason: String) {
        self.planID = planID
        self.title = title
        self.workdir = workdir
        self.reason = reason
    }
}

public enum RoomSource {
    private struct CacheState: Sendable {
        var activeRooms: [ActiveRoomEntry] = []
        var fileCache: [URL: (mtime: Date, entries: [ActiveRoomEntry])] = [:]
    }
    
    private static let cacheLock = OSAllocatedUnfairLock(initialState: CacheState())

    private static func readEntriesFromFiles(
        _ fileInfos: [(URL, Date)],
        oldCache: [URL: (mtime: Date, entries: [ActiveRoomEntry])],
        maxRooms: Int
    ) -> (results: [ActiveRoomEntry], newCache: [URL: (mtime: Date, entries: [ActiveRoomEntry])]) {
        var results: [ActiveRoomEntry] = []
        var newFileCache: [URL: (mtime: Date, entries: [ActiveRoomEntry])] = [:]

        for (fileURL, mtime) in fileInfos.prefix(60) {
            let entries: [ActiveRoomEntry]
            if let old = oldCache[fileURL], old.mtime == mtime {
                entries = old.entries
            } else {
                entries = parsePlacementFile(at: fileURL)
            }
            newFileCache[fileURL] = (mtime, entries)
            results.append(contentsOf: entries)
            if results.count >= maxRooms * 2 { break }
        }
        return (results, newFileCache)
    }

    public static func loadActiveRoomsFromDisk(maxRooms: Int = 12) -> [ActiveRoomEntry] {
        let path = StateRootKit.hostPath(".agent-work-todo/store-v2/placements")
        let placementsDir = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
            return listActiveRooms()
        }

        let files = (try? FileManager.default.contentsOfDirectory(
            at: placementsDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        )) ?? []

        let fileInfos = files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> (URL, Date)? in
                guard let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate else { return nil }
                return (url, mtime)
            }
            .sorted { $0.1 > $1.1 }

        let oldCache = cacheLock.withLock { $0.fileCache }
        let (results, newFileCache) = readEntriesFromFiles(fileInfos, oldCache: oldCache, maxRooms: maxRooms)

        guard !results.isEmpty else {
            let fallback = listActiveRooms()
            cacheLock.withLock { state in
                state.activeRooms = fallback
                state.fileCache = [:]
            }
            return fallback
        }

        let sorted = results.sorted { $0.isOccupied && !$1.isOccupied }
        let finalRooms = Array(sorted.prefix(maxRooms))

        cacheLock.withLock { state in
            state.activeRooms = finalRooms
            state.fileCache = newFileCache
        }

        return finalRooms
    }

    private static let excludedRoomStates: Set<String> = ["missing", "exited", "closed", "failed"]
    private static let activeRoomStates: Set<String> = [
        "occupied", "waiting", "gated", "blocked", "escalated", "planned"
    ]
    private static let excludedPlacementStates: Set<String> = [
        "completed", "rejected", "abandoned", "failed", "dismantled", "closed", "exited"
    ]

    public static func loadLifecycleCleanupIssuesFromDisk(maxIssues: Int = 20) -> [RoomLifecycleCleanupIssue] {
        let path = StateRootKit.hostPath(".agent-work-todo/store-v2/placements")
        let directory = URL(fileURLWithPath: path)
        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: .skipsHiddenFiles
            )
        } catch {
            files = []
        }
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> (Date, RoomLifecycleCleanupIssue)? in
                let data: Data
                let date: Date
                do {
                    data = try Data(contentsOf: url)
                    date = try url.resourceValues(forKeys: [.contentModificationDateKey])
                        .contentModificationDate ?? .distantPast
                } catch {
                    return nil
                }
                guard let issue = decodeLifecycleCleanupIssue(from: data) else { return nil }
                return (date, issue)
            }
            .sorted { $0.0 > $1.0 }
            .prefix(max(0, maxIssues))
            .map(\.1)
    }

    public static func decodeLifecycleCleanupIssue(from data: Data) -> RoomLifecycleCleanupIssue? {
        let plan: [String: Any]
        do {
            guard let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            plan = decoded
        } catch {
            return nil
        }
        guard let notes = plan["tickNotes"] as? [String],
              let failure = notes.last(where: {
                  $0.hasPrefix("[lifecycle-cleanup-failed]") ||
                      $0.hasPrefix("[worktree-close-failed]")
              })
        else { return nil }
        let prefix = failure.hasPrefix("[lifecycle-cleanup-failed]")
            ? "[lifecycle-cleanup-failed]"
            : "[worktree-close-failed]"
        let reason = failure.dropFirst(prefix.count)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return RoomLifecycleCleanupIssue(
            planID: plan["id"] as? String ?? "unknown-plan",
            title: plan["title"] as? String ?? "종결 Room",
            workdir: plan["workdir"] as? String ?? "",
            reason: reason.isEmpty ? "Room 생명주기 정리 미확인" : reason)
    }

    private static func noteMatchesRoom(note: String, roomID: String, blueprintSlug: String) -> Bool {
        let matchesSlug = !blueprintSlug.isEmpty && note.contains(blueprintSlug)
        let matchesID = !roomID.isEmpty && note.contains(roomID)
        return matchesSlug || matchesID
    }

    public static func isZombieOrInactive(
        roomID: String,
        blueprintSlug: String,
        roomState: String,
        tickNotes: [String]
    ) -> Bool {
        let normalizedState = roomState.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !excludedRoomStates.contains(normalizedState),
              activeRoomStates.contains(normalizedState) else {
            return true
        }
        for note in tickNotes where noteMatchesRoom(note: note, roomID: roomID, blueprintSlug: blueprintSlug) {
            let isExpired = note.contains("세션 종료") || note.contains("5분 초과")
            if isExpired { return true }
        }
        return false
    }

    private static func parsePlacementFile(at fileURL: URL) -> [ActiveRoomEntry] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let obj: [String: Any]
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
            obj = json
        } catch {
            return []
        }

        guard let rawState = obj["state"] as? String else { return [] }
        let normalizedState = rawState.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !excludedPlacementStates.contains(normalizedState) else { return [] }

        let plan = obj
        let planID = plan["id"] as? String ?? fileURL.deletingPathExtension().lastPathComponent
        let title = plan["title"] as? String ?? ""
        let tenantID = plan["tenantID"] as? String ?? plan["tenant_id"] as? String ?? plan["tenant"] as? String ?? ""
        let planWorkdir = plan["workdir"] as? String
        let tickNotes = plan["tickNotes"] as? [String] ?? []

        guard let rooms = obj["rooms"] as? [[String: Any]], !rooms.isEmpty else {
            return [ActiveRoomEntry(
                id: planID,
                planID: planID,
                title: title,
                blueprintSlug: "",
                occupant: "",
                occupantHandle: "",
                workdir: planWorkdir,
                state: rawState,
                handoverState: "none",
                tenantID: tenantID
            )]
        }

        return rooms.compactMap { room in
            let roomID = room["id"] as? String ?? UUID().uuidString
            let blueprintSlug = room["blueprintSlug"] as? String ?? ""
            let occupant = room["occupant"] as? String ?? ""
            let occupantHandle = room["occupantHandle"] as? String ?? ""
            let roomWorkdir = room["workdir"] as? String ?? planWorkdir
            let roomState = room["state"] as? String ?? "occupied"
            let handoverState = room["handoverState"] as? String ?? "none"
            let effectiveTenantID = room["tenantID"] as? String ?? room["tenant_id"] as? String ?? room["tenant"] as? String ?? tenantID

            if isZombieOrInactive(
                roomID: roomID,
                blueprintSlug: blueprintSlug,
                roomState: roomState,
                tickNotes: tickNotes
            ) {
                return nil
            }

            let resolvedTitle = RoomTitleResolver.resolveTitle(
                roomDict: room,
                planTitle: title,
                blueprintSlug: blueprintSlug,
                occupantHandle: occupantHandle,
                occupant: occupant
            )

            return ActiveRoomEntry(
                id: roomID,
                planID: planID,
                title: resolvedTitle,
                blueprintSlug: blueprintSlug,
                occupant: occupant,
                occupantHandle: occupantHandle,
                workdir: roomWorkdir,
                state: roomState,
                handoverState: handoverState,
                tenantID: effectiveTenantID
            )
        }
    }

    public static func listActiveRooms(
        cliPath: String = HostPlatform.cliBinPath("agent-work-todo")
    ) -> [ActiveRoomEntry] {
        guard FileManager.default.isExecutableFile(atPath: cliPath) else {
            return []
        }
        let result = CommandKitSync.run(cliPath, ["placement", "list", "--json"], timeout: 2)
        guard result.exitCode == 0, let data = result.stdout.data(using: .utf8) else {
            return []
        }
        return decodeActiveRooms(from: data)
    }

    public static func listActiveRoomsAsync(
        cliPath: String = HostPlatform.cliBinPath("agent-work-todo")
    ) async -> [ActiveRoomEntry] {
        await Task.detached(priority: .userInitiated) {
            listActiveRooms(cliPath: cliPath)
        }.value
    }

    private static func parseSingleRoom(
        _ room: [String: Any],
        planID: String,
        planTitle: String,
        defaultTenantID: String,
        defaultWorkdir: String?,
        tickNotes: [String]
    ) -> ActiveRoomEntry? {
        let roomID = room["id"] as? String ?? UUID().uuidString
        let blueprintSlug = room["blueprintSlug"] as? String ?? ""
        let state = room["state"] as? String ?? "occupied"

        guard !isZombieOrInactive(
            roomID: roomID,
            blueprintSlug: blueprintSlug,
            roomState: state,
            tickNotes: tickNotes
        ) else {
            return nil
        }

        let occupant = room["occupant"] as? String ?? ""
        let occupantHandle = room["occupantHandle"] as? String ?? ""
        let roomWorkdir = room["workdir"] as? String ?? defaultWorkdir
        let handoverState = room["handoverState"] as? String ?? "none"
        let effectiveTenantID = room["tenantID"] as? String ?? room["tenant_id"] as? String ?? room["tenant"] as? String ?? defaultTenantID

        let resolvedTitle = RoomTitleResolver.resolveTitle(
            roomDict: room,
            planTitle: planTitle,
            blueprintSlug: blueprintSlug,
            occupantHandle: occupantHandle,
            occupant: occupant
        )

        return ActiveRoomEntry(
            id: roomID,
            planID: planID,
            title: resolvedTitle,
            blueprintSlug: blueprintSlug,
            occupant: occupant,
            occupantHandle: occupantHandle,
            workdir: roomWorkdir,
            state: state,
            handoverState: handoverState,
            tenantID: effectiveTenantID
        )
    }

    private static func parsePlanEntries(_ plan: [String: Any]) -> [ActiveRoomEntry] {
        let planID = plan["id"] as? String ?? ""
        let title = plan["title"] as? String ?? ""
        let tenantID = plan["tenantID"] as? String ?? plan["tenant_id"] as? String ?? plan["tenant"] as? String ?? ""
        let planWorkdir = plan["workdir"] as? String
        let tickNotes = plan["tickNotes"] as? [String] ?? []
        let rawPlanState = plan["state"] as? String ?? "executing"
        let normalizedPlanState = rawPlanState.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !excludedPlacementStates.contains(normalizedPlanState) else { return [] }

        guard let rooms = plan["rooms"] as? [[String: Any]], !rooms.isEmpty else {
            return [
                ActiveRoomEntry(
                    id: planID,
                    planID: planID,
                    title: title,
                    blueprintSlug: "",
                    occupant: "",
                    occupantHandle: "",
                    workdir: planWorkdir,
                    state: rawPlanState,
                    handoverState: "none",
                    tenantID: tenantID
                )
            ]
        }

        return rooms.compactMap { room in
            parseSingleRoom(
                room,
                planID: planID,
                planTitle: title,
                defaultTenantID: tenantID,
                defaultWorkdir: planWorkdir,
                tickNotes: tickNotes
            )
        }
    }

    public static func decodeActiveRooms(from data: Data) -> [ActiveRoomEntry] {
        do {
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let list = obj["payload"] as? [[String: Any]] else {
                return []
            }
            return list.flatMap(parsePlanEntries)
        } catch {
            return []
        }
    }

}

public extension RoomSource {
    static func openWorkdir(path: String) {
        guard !path.isEmpty else { return }
        Task.detached(priority: .userInitiated) {
            _ = CommandKitSync.run("/usr/bin/open", [path], timeout: 4)
        }
    }

    internal static func terminalEnvironment(roomID: String? = nil, tenantID: String? = nil) -> [String: String] {
        var env: [String: String] = [:]
        if let tenantID, !tenantID.isEmpty {
            let tenant = tenantID.isEmpty ? "default" : tenantID
            let stateRoot = StateRootKit.tenantStateRoot(tenant: tenant)
            env["SWIFT_APP_STATE_ROOT"] = stateRoot
            env["ROOM_TENANT"] = tenant
            env["AGENT_TENANT"] = tenant
            env["TENANT_ID"] = tenant
        }
        if let roomID = roomID?.trimmingCharacters(in: .whitespacesAndNewlines), !roomID.isEmpty {
            env["ROOM_ID"] = roomID.hasPrefix("room-") ? String(roomID.dropFirst(5)) : roomID
        }
        return env
    }

    static func openTerminal(path: String, tenantID: String? = nil, roomID: String? = nil) {
        let env = terminalEnvironment(roomID: roomID, tenantID: tenantID)
        RoomActionRouter.openRoomSync(path: path, environment: env)
    }

    static func decideGate(
        planID: String,
        roomID: String,
        approve: Bool,
        by: String? = nil
    ) -> (ok: Bool, output: String) {
        let action = approve ? "approve" : "deny"
        let cli = HostPlatform.cliBinPath("agent-work-todo")
        guard FileManager.default.isExecutableFile(atPath: cli) else {
            return (false, "agent-work-todo CLI not found")
        }
        var args = ["gate", action, "--plan", planID, "--room", roomID]
        if let by, !by.isEmpty {
            args.append(contentsOf: ["--by", by])
        }
        let res = CommandKitSync.run(cli, args, timeout: 10)
        return (res.exitCode == 0, res.stdout + res.stderr)
    }
}

/// 에이전트에게 마련한 공간 — Grok Bot의 "봇마다 컴퓨터 한 대"에 해당하는 로컬 자리.
/// 정본은 `agent-seat-manager seats`. 폴더(workdir)가 있는 자리만 연다.
public struct SeatSpaceEntry: Sendable, Equatable, Identifiable {
    public var id: String { handle }
    public let handle: String
    public let occupant: String
    public let workdir: String?

    public init(handle: String, occupant: String, workdir: String?) {
        self.handle = handle
        self.occupant = occupant
        self.workdir = workdir
    }
}

public enum SeatSpaceError: Error, Equatable, LocalizedError {
    case emptyHandle
    case cliMissing(String)
    case commandFailed(String)

    public var errorDescription: String? {
        switch self {
        case .emptyHandle:
            return "empty handle"
        case .cliMissing(let path):
            return "missing CLI: \(path)"
        case .commandFailed(let detail):
            return detail
        }
    }
}

public enum SeatSpace {
    public static func defaultWorkdir(
        handle: String,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        let safe = handle
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return home
            .appendingPathComponent("AgentSpaces", isDirectory: true)
            .appendingPathComponent(safe, isDirectory: true)
    }

    public static func assignFolder(
        handle: String,
        cliPath: String = HostPlatform.cliBinPath("agent-seat-manager"),
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) -> Result<String, SeatSpaceError> {
        let trimmed = handle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.emptyHandle) }
        let folder = defaultWorkdir(handle: trimmed, home: home)
        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            return .failure(.commandFailed(error.localizedDescription))
        }
        guard fileManager.isExecutableFile(atPath: cliPath) else {
            return .failure(.cliMissing(cliPath))
        }
        let result = CommandKitSync.run(cliPath, ["rebind", trimmed, "--dir", folder.path], timeout: 4)
        if result.exitCode != 0 {
            let raw = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if raw.isEmpty {
                return .failure(.commandFailed("rebind exit \(result.exitCode)"))
            }
            return .failure(.commandFailed(raw))
        }
        return .success(folder.path)
    }

    public static func listSeats(cliPath: String = HostPlatform.cliBinPath("agent-seat-manager")) -> [SeatSpaceEntry] {
        guard FileManager.default.isExecutableFile(atPath: cliPath) else {
            return []
        }
        let result = CommandKitSync.run(cliPath, ["seats", "--json"], timeout: 2)
        guard result.exitCode == 0, let data = result.stdout.data(using: .utf8) else {
            return []
        }
        return decodeSeats(from: data)
    }

    public static func listSeatsAsync(
        cliPath: String = HostPlatform.cliBinPath("agent-seat-manager")
    ) async -> [SeatSpaceEntry] {
        await Task.detached(priority: .userInitiated) {
            listSeats(cliPath: cliPath)
        }.value
    }

    public static func decodeSeats(from data: Data) -> [SeatSpaceEntry] {
        let json: Any
        do {
            json = try JSONSerialization.jsonObject(with: data)
        } catch {
            return []
        }
        let rows: [[String: Any]]
        if let list = json as? [[String: Any]] {
            rows = list
        } else if let obj = json as? [String: Any] {
            let inner = obj["result"] ?? obj["payload"] ?? obj["seats"]
            rows = inner as? [[String: Any]] ?? []
        } else {
            return []
        }
        return rows.compactMap { row in
            guard let handle = row["handle"] as? String, !handle.isEmpty else { return nil }
            let occupant = row["occupant"] as? String ?? ""
            let workdir = row["workdir"] as? String
            return SeatSpaceEntry(handle: handle, occupant: occupant, workdir: workdir)
        }
    }
}
