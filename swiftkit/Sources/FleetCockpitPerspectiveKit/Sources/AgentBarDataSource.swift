import Foundation
import os
import StateRootKit

/// 대화형 AI 에이전트 세션(Claude, Agy, Codex)을 제공하는 데이터 소스
public final class AgentBarDataSource: BarDataSourceProtocol, Sendable {
    public let mode: BarMode = .agentBar
    private let store: InvertedStateStore
    private let contLock = OSAllocatedUnfairLock<AsyncStream<[UnifiedBarItem]>.Continuation?>(initialState: nil)

    public init(store: InvertedStateStore = .shared) {
        self.store = store
        store.addListener { [weak self] in
            guard let self else { return }
            _ = self.contLock.withLock { $0?.yield(self.currentItems()) }
        }
    }

    public func currentItems() -> [UnifiedBarItem] {
        let agents = store.currentAgents()
        if agents.isEmpty {
            return fallbackItems()
        }
        let baseItems = agents.map { a in
            let toolName = a.tool ?? "agent"
            let dot: BarStatusDot
            switch a.status?.lowercased() {
            case "idle":
                dot = .idle
            case "waiting":
                dot = .waiting
            case "error":
                dot = .error
            case "done":
                dot = .none
            default:
                dot = .running
            }

            let badge: BarBadge? = a.container == "Ghostty" ? BarBadge(text: "Ghostty", kind: .count) : nil

            return UnifiedBarItem(
                id: "agent-\(a.pid)",
                title: "\(toolName) #\(a.pid)",
                subtitle: a.projectName,
                icon: .symbol("sparkles"),
                statusDot: dot,
                badge: badge,
                subjobCount: a.subjobCount,
                runningSubjobCount: a.runningSubjobCount,
                workdir: a.cwd
            )
        }
        return HostAgentTreeScanner.shared.cachedTree(baseAgents: baseItems)
    }

    public var itemsStream: AsyncStream<[UnifiedBarItem]> {
        AsyncStream { [weak self] cont in
            _ = self?.contLock.withLock { $0 = cont }
            cont.yield(self?.currentItems() ?? [])
        }
    }

    public func activate() async {
        store.startAutoRefresh(intervalSeconds: 2.0)
        _ = contLock.withLock { $0?.yield(currentItems()) }
    }

    public func deactivate() {
        store.stopAutoRefresh()
    }

    private func fallbackItems() -> [UnifiedBarItem] {
        let rooms = store.currentRooms()
        let awoJobs = store.currentAwoJobs()

        var items: [UnifiedBarItem] = []
        let occupiedRooms = rooms.filter { $0.isOccupied }

        for room in occupiedRooms {
            let matchedJobs = awoJobs.filter { job in
                if let rw = room.workdir, let jw = job.workdir, !rw.isEmpty, rw == jw { return true }
                if let rw = room.workdir, !rw.isEmpty, job.title.contains(rw) { return true }
                if !room.blueprintSlug.isEmpty, job.title.localizedCaseInsensitiveContains(room.blueprintSlug) { return true }
                return false
            }

            let running = matchedJobs.filter { $0.isRunning }.count
            items.append(
                UnifiedBarItem(
                    id: "agent-\(room.id)",
                    title: room.shortOccupant.isEmpty ? "Agent" : room.shortOccupant,
                    subtitle: room.cleanTitle,
                    icon: .symbol("sparkles"),
                    statusDot: .running,
                    badge: nil,
                    subjobCount: matchedJobs.count,
                    runningSubjobCount: running,
                    workdir: room.workdir
                )
            )
        }

        return items
    }
}
