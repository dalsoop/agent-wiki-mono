import Foundation
import os
import StateRootKit

/// 동기 CLI 호출을 배제하고 StateMirror 파일 및 실시간 프로세스 트리 기반 In-Memory 캐시를 제공하는 비동기 스토어
public struct AgentSessionEntry: Equatable, Sendable, Identifiable {
    public var id: Int32 { pid }
    public var pid: Int32
    public var tool: String?
    public var projectName: String?
    public var cwd: String?
    public var subjobCount: Int
    public var runningSubjobCount: Int
    public var sessionID: String?
    public var status: String?
    public var container: String?
    public var model: String?
    public var subagents: [AgentSessionEntry]

    public init(
        pid: Int32,
        tool: String? = nil,
        projectName: String? = nil,
        cwd: String? = nil,
        subjobCount: Int = 0,
        runningSubjobCount: Int = 0,
        sessionID: String? = nil,
        status: String? = nil,
        container: String? = nil,
        model: String? = nil,
        subagents: [AgentSessionEntry] = []
    ) {
        self.pid = pid
        self.tool = tool
        self.projectName = projectName
        self.cwd = cwd
        self.subjobCount = subjobCount
        self.runningSubjobCount = runningSubjobCount
        self.sessionID = sessionID
        self.status = status
        self.container = container
        self.model = model
        self.subagents = subagents
    }
}

public final class InvertedStateStore: Sendable {
    public static let shared = InvertedStateStore()
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "fleetdock", category: "state-store")

    private struct State: Sendable {
        var rooms: [ActiveRoomEntry] = []
        var awoJobs: [AwoJobEntry] = []
        var agents: [AgentSessionEntry] = []
        var lastUpdated: Date = .distantPast
        var listeners: [@Sendable () -> Void] = []
        var lastAwoMtime: Date = .distantPast
        var lastAgentMtime: Date = .distantPast
    }

    private let lock: OSAllocatedUnfairLock<State>
    private let updateTaskLock: OSAllocatedUnfairLock<Task<Void, Never>?>

    public init() {
        self.lock = OSAllocatedUnfairLock(initialState: State())
        self.updateTaskLock = OSAllocatedUnfairLock(initialState: nil)
    }

    deinit {
        updateTaskLock.withLock { $0?.cancel() }
    }

    public func addListener(_ listener: @escaping @Sendable () -> Void) {
        lock.withLock {
            $0.listeners.append(listener)
        }
    }

    private func notifyListeners() {
        let currentListeners = lock.withLock { $0.listeners }
        for listener in currentListeners {
            listener()
        }
    }

    public func currentRooms() -> [ActiveRoomEntry] {
        lock.withLock { $0.rooms }
    }

    public func currentAgents() -> [AgentSessionEntry] {
        lock.withLock { $0.agents }
    }

    public func currentAwoJobs() -> [AwoJobEntry] {
        lock.withLock { $0.awoJobs }
    }

    /// 테넌트별로 그룹화된 방 및 하위 바 아이템 계층 목록을 반환
    public func currentTenantRoomGroups() -> [TenantRoomGroup] {
        let rooms = currentRooms()
        let jobs = currentAwoJobs()

        var roomsByTenant: [String: [ActiveRoomEntry]] = [:]
        for r in rooms {
            let tKey = r.tenantID.isEmpty ? "tenant:default" : r.tenantID
            roomsByTenant[tKey, default: []].append(r)
        }

        var groups: [TenantRoomGroup] = []
        for (tKey, tenantRooms) in roomsByTenant.sorted(by: { $0.key < $1.key }) {
            let context = TenantContext(slug: tKey)
            let tenantJobs = jobs.filter { j in
                if let jt = j.tenantID, !jt.isEmpty {
                    return jt == tKey || jt == context.slug
                }
                return true
            }
            let barItems = AttributionEngine.attribute(rooms: tenantRooms, awoJobs: tenantJobs)
            groups.append(TenantRoomGroup(
                tenant: context,
                rooms: tenantRooms,
                barItems: barItems
            ))
        }
        return groups
    }

    public func reloadOnce() {
        let newRooms = loadRoomsFromMirror()
        let newJobs = loadAwoJobsFromMirror()
        let newAgents = loadAgentsFromMirror()

        let changed = lock.withLock { state -> Bool in
            let anyDiff = [state.rooms != newRooms, state.awoJobs != newJobs, state.agents != newAgents]
            guard anyDiff.contains(true) else { return false }
            state.rooms = newRooms
            state.awoJobs = newJobs
            state.agents = newAgents
            state.lastUpdated = Date()
            return true
        }

        if changed {
            notifyListeners()
        }
    }

    public func startAutoRefresh(intervalSeconds: TimeInterval = 2.0) {
        let alreadyRunning = updateTaskLock.withLock { $0 != nil }
        guard !alreadyRunning else { return }
        let task = Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            self.reloadOnce()
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: UInt64(intervalSeconds * 1_000_000_000))
                } catch {
                    break
                }
                guard !Task.isCancelled else { break }
                self.reloadOnce()
            }
        }
        updateTaskLock.withLock { $0 = task }
    }

    public func stopAutoRefresh() {
        updateTaskLock.withLock {
            $0?.cancel()
            $0 = nil
        }
    }

    // MARK: - 내부 파일 로더

    private func loadAgentsFromMirror() -> [AgentSessionEntry] {
        let scanResult = HostAgentTreeScanner.shared.scan()
        let activeRooms = loadRoomsFromMirror().filter { $0.isOccupied }
        let (decodedSessions, latestMtime) = InvertedStateScanner.decodeAgentSessionsFromFiles(
            urls: InvertedStateScanner.candidateAgentFiles()
        )

        if latestMtime > .distantPast {
            lock.withLock { state in
                if latestMtime > state.lastAgentMtime { state.lastAgentMtime = latestMtime }
            }
        }

        guard scanResult.agents.isEmpty else {
            return InvertedStateScanner.synthesizeAgentEntries(from: scanResult.agents, activeRooms: activeRooms)
        }

        return decodedSessions.filter { $0.pid > 0 }.map { session in
            AgentSessionEntry(
                pid: session.pid,
                tool: session.tool ?? "agent",
                projectName: session.projectName,
                cwd: session.cwd
            )
        }
    }

    private func loadAwoJobsFromMirror() -> [AwoJobEntry] {
        let candidates = InvertedStateScanner.candidateAwoFiles()
        guard !candidates.isEmpty else { return [] }

        var bestURL: URL?
        var bestMtime = Date.distantPast

        for url in candidates {
            guard let vals = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                  let mtime = vals.contentModificationDate, mtime > bestMtime else { continue }
            bestMtime = mtime
            bestURL = url
        }

        let lastAwoMtime = lock.withLock { $0.lastAwoMtime }
        guard bestMtime <= .distantPast || bestMtime != lastAwoMtime else {
            return lock.withLock { $0.awoJobs }
        }

        guard let selectedURL = bestURL, let data = try? Data(contentsOf: selectedURL) else {
            return []
        }

        let parsed = InvertedStateScanner.parseAwoData(data)
        let finalAwoMtime = bestMtime
        lock.withLock { state in
            state.lastAwoMtime = finalAwoMtime
        }
        return parsed
    }

    private func loadRoomsFromMirror() -> [ActiveRoomEntry] {
        let diskRooms = RoomSource.loadActiveRoomsFromDisk()
        let rooms: [ActiveRoomEntry]
        if diskRooms.isEmpty {
            rooms = InvertedStateScanner.candidateRoomFiles().lazy.compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                let entries = RoomSource.decodeActiveRooms(from: data)
                return entries.isEmpty ? nil : entries
            }.first ?? []
        } else {
            rooms = diskRooms
        }

        let bindings = InvertedStateScanner.decodeRoomAgentBindingsFromFiles(
            urls: InvertedStateScanner.candidateRoomGraphFiles()
        )
        return InvertedStateScanner.enrichRooms(rooms, with: bindings)
    }
}
