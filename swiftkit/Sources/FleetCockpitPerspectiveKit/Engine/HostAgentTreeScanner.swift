import Foundation
import os
import CommandKit
import StateRootKit
import InteropKit

/// 호스트에서 Ghostty, herdr, tmux, PTY(ttys*) 계통 및 실행 중인 AI 에이전트를 탐지하는 스캐너
public final class HostAgentTreeScanner: Sendable {
    public static let shared = HostAgentTreeScanner()
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "fleetdock", category: "agent-tree-scanner")

    public static let knownAgentNames: Set<String> = [
        "claude", "claude-code", "agy", "antigravity", "codex", "grok", "glm", "gemini", "cursor", "windsurf"
    ]

    private let tableProvider: (@Sendable () -> String)?
    private let herdrProvider: (@Sendable () -> String?)?
    private let cwdProvider: (@Sendable ([Int32]) -> [Int32: String])?

    private struct CacheState: Sendable {
        var lastResult: HostAgentTreeScanResult?
        var lastScanTime: Date = .distantPast
        var cwdMapCache: [Int32: (cwd: String, cachedAt: Date)] = [:]
    }

    private let cacheLock = OSAllocatedUnfairLock(initialState: CacheState())
    public let cacheTTL: TimeInterval

    public init(
        tableProvider: (@Sendable () -> String)? = nil,
        herdrProvider: (@Sendable () -> String?)? = nil,
        cwdProvider: (@Sendable ([Int32]) -> [Int32: String])? = nil,
        cacheTTL: TimeInterval = 1.5
    ) {
        self.tableProvider = tableProvider
        self.herdrProvider = herdrProvider
        self.cwdProvider = cwdProvider
        self.cacheTTL = cacheTTL
    }

    public func invalidateCache() {
        cacheLock.withLock { state in
            state.lastResult = nil
            state.lastScanTime = .distantPast
            state.cwdMapCache.removeAll()
        }
    }

    // MARK: - 시스템 프로세스 테이블 수집
    public static func fetchSystemProcessTable() -> String {
        let psResult = CommandKitSync.run("/bin/ps", ["-axww", "-o", "pid=,ppid=,tty=,args="], timeout: 5)
        if psResult.exitCode == 0, !psResult.stdout.isEmpty {
            return psResult.stdout
        }
        return ""
    }

    // MARK: - 프로세스 CLI 인자 모델 탐지
    public static func detectProcessModel(pid: Int32, command: String) -> String? {
        let tokens = command.split(whereSeparator: \.isWhitespace).map(String.init)
        for j in 0..<tokens.count {
            let tok = tokens[j]
            let isModelFlag = (tok == "--model" || tok == "-m")
            guard isModelFlag, j + 1 < tokens.count else { continue }
            let val = tokens[j + 1]
            if !val.hasPrefix("-") {
                return val
            }
        }
        return nil
    }

    // MARK: - 메인 스캔 실행
    public func scan(forceRefresh: Bool = false) -> HostAgentTreeScanResult {
        let isCustom = (tableProvider != nil || herdrProvider != nil || cwdProvider != nil)
        if !forceRefresh && !isCustom {
            let cached = cacheLock.withLock { state -> HostAgentTreeScanResult? in
                guard let res = state.lastResult, Date().timeIntervalSince(state.lastScanTime) < self.cacheTTL else {
                    return nil
                }
                return res
            }
            if let cached {
                return cached
            }
        }

        let rawTable = tableProvider?() ?? Self.fetchSystemProcessTable()
        guard !rawTable.isEmpty else {
            return HostAgentTreeScanResult(agents: [], lineages: [], totalAgentCount: 0, ghosttyPID: nil, herdrServerPID: nil)
        }

        let records = HostAgentTreeBuilder.parseProcessTable(rawTable)
        let lineages = HostAgentTreeBuilder.extractLineages(from: records)

        var allTargetPids: Set<Int32> = []
        for l in lineages {
            allTargetPids.insert(l.claudePID)
            for s in l.subagentPIDs {
                allTargetPids.insert(s)
            }
        }

        let cwdMap = resolveCWDMap(for: Array(allTargetPids))
        let herdrJson = herdrProvider?() ?? Self.fetchHerdrPanesJSON()

        let result = HostAgentTreeBuilder.buildScanResult(
            records: records,
            lineages: lineages,
            cwdMap: cwdMap,
            herdrJson: herdrJson
        )

        if !isCustom {
            cacheLock.withLock { state in
                state.lastResult = result
                state.lastScanTime = Date()
            }
        }

        return result
    }

    /// 현재 메모리 캐시 스냅샷을 0ms로 즉시 반환한다 (TTL 만료 시 nil).
    public func cachedResult() -> HostAgentTreeScanResult? {
        cacheLock.withLock { state -> HostAgentTreeScanResult? in
            guard let res = state.lastResult, Date().timeIntervalSince(state.lastScanTime) < self.cacheTTL else {
                return nil
            }
            return res
        }
    }

    /// 백그라운드 태스크에서 비동기로 스캔하여 메인 스레드 비치볼을 방지한다.
    public func scanAsync(forceRefresh: Bool = false) async -> HostAgentTreeScanResult {
        await Task.detached(priority: .userInitiated) {
            self.scan(forceRefresh: forceRefresh)
        }.value
    }

    private func resolveCWDMap(for pids: [Int32]) -> [Int32: String] {
        if let cwdProvider {
            return cwdProvider(pids)
        }
        guard !pids.isEmpty else { return [:] }

        let now = Date()
        let (cached, missing) = cacheLock.withLock { state -> ([Int32: String], [Int32]) in
            var found: [Int32: String] = [:]
            var needed: [Int32] = []
            for pid in pids {
                if let entry = state.cwdMapCache[pid], now.timeIntervalSince(entry.cachedAt) < 5.0 {
                    found[pid] = entry.cwd
                } else {
                    needed.append(pid)
                }
            }
            return (found, needed)
        }

        var cachedMap = cached
        guard !missing.isEmpty else { return cachedMap }

        let freshMap = Self.fetchCWDMap(for: missing)
        cacheLock.withLock { state in
            for (pid, cwd) in freshMap {
                state.cwdMapCache[pid] = (cwd: cwd, cachedAt: now)
            }
        }
        for (pid, cwd) in freshMap {
            cachedMap[pid] = cwd
        }
        return cachedMap
    }

    public static func fetchCWDMap(for pids: [Int32]) -> [Int32: String] {
        guard !pids.isEmpty else { return [:] }
        let pidArgs = pids.map(String.init).joined(separator: ",")
        let lsofResult = CommandKitSync.run("/usr/sbin/lsof", ["-a", "-p", pidArgs, "-d", "cwd", "-Fn"], timeout: 3)
        guard lsofResult.exitCode == 0, !lsofResult.stdout.isEmpty else { return [:] }

        var map: [Int32: String] = [:]
        var currentPid: Int32?
        for line in lsofResult.stdout.split(separator: "\n") {
            if line.hasPrefix("p"), let p = Int32(line.dropFirst()) {
                currentPid = p
            } else if line.hasPrefix("n"), let cur = currentPid {
                map[cur] = String(line.dropFirst())
            }
        }
        return map
    }

    public static func fetchHerdrPanesJSON() -> String? {
        let candidates = [
            HostPlatform.cliBinPath("herdr"),
            "\(HostPlatform.homebrewBin)/herdr",
            "/usr/local/bin/herdr",
            "herdr"
        ]
        for bin in candidates {
            let res = CommandKitSync.run(bin, ["pane", "list", "--json"], timeout: 2)
            if res.exitCode == 0, !res.stdout.isEmpty {
                return res.stdout
            }
        }
        return nil
    }

    package static func fetchHerdrPaneProcessInfo(paneID: String) -> (fgPgid: Int32?, shellPid: Int32?, fgPids: [Int32])? {
        let candidates = [
            HostPlatform.cliBinPath("herdr"),
            "\(HostPlatform.homebrewBin)/herdr",
            "/usr/local/bin/herdr",
            "herdr"
        ]
        for bin in candidates {
            let res = CommandKitSync.run(bin, ["pane", "process-info", "--pane", paneID], timeout: 2)
            guard res.exitCode == 0, !res.stdout.isEmpty, let data = res.stdout.data(using: .utf8) else { continue }
            do {
                let decoded = try JSONDecoder().decode(HerdrProcessInfoResponse.self, from: data)
                if let pinfo = decoded.result?.process_info {
                    let fgPids = pinfo.foreground_processes?.compactMap { $0.pid } ?? []
                    return (pinfo.foreground_process_group_id, pinfo.shell_pid, fgPids)
                }
            } catch {
                continue
            }
        }
        return nil
    }

    // MARK: - 포워딩 정적 API (하위 호환성 유지)
    public static func parseProcessTable(_ raw: String) -> [ProcessRecord] {
        HostAgentTreeBuilder.parseProcessTable(raw)
    }

    public static func buildTree(from records: [ProcessRecord]) -> [AgentTreeNode] {
        HostAgentTreeBuilder.buildTree(from: records)
    }

    public static func detectRole(_ command: String) -> ProcessRole {
        HostAgentTreeBuilder.detectRole(command)
    }

    public static func extractLineages(from records: [ProcessRecord]) -> [AgentLineage] {
        HostAgentTreeBuilder.extractLineages(from: records)
    }

    public static func buildScanResult(
        records: [ProcessRecord],
        lineages: [AgentLineage],
        cwdMap: [Int32: String],
        herdrJson: String?
    ) -> HostAgentTreeScanResult {
        HostAgentTreeBuilder.buildScanResult(records: records, lineages: lineages, cwdMap: cwdMap, herdrJson: herdrJson)
    }

    public static func extractSubagentTitle(command: String, cwd: String? = nil) -> String {
        HostAgentTitleExtractor.extractSubagentTitle(command: command, cwd: cwd)
    }

    public static func extractSubagentTitle(command: String) -> String {
        HostAgentTitleExtractor.extractSubagentTitle(command: command, cwd: nil)
    }

    // MARK: - UnifiedBarItem 트리 계층 합성 & 터미널 귀속
    public func scanTree(
        baseAgents: [UnifiedBarItem],
        scanResult: HostAgentTreeScanResult? = nil
    ) -> [UnifiedBarItem] {
        let result = scanResult ?? self.scan()
        let agentMap = Dictionary(uniqueKeysWithValues: result.agents.map { ($0.pid, $0) })

        var results: [UnifiedBarItem] = []
        for parent in baseAgents {
            guard parent.children.isEmpty else {
                results.append(parent)
                continue
            }

            let parentPid = extractPIDFromItemID(parent.id)
            var children: [UnifiedBarItem] = []
            if let pid = parentPid, let matchedAgent = agentMap[pid], !matchedAgent.subagents.isEmpty {
                children = Self.convertSubagentsToBarItems(matchedAgent.subagents, parentIdPrefix: parent.id)
            }

            let matchedAgent = parentPid.flatMap { agentMap[$0] }
            let itemModel = parent.model ?? matchedAgent?.model

            results.append(
                UnifiedBarItem(
                    id: parent.id,
                    title: parent.title,
                    subtitle: parent.subtitle,
                    icon: parent.icon,
                    statusDot: parent.statusDot,
                    badge: parent.badge,
                    subjobCount: max(parent.subjobCount, children.count),
                    runningSubjobCount: max(parent.runningSubjobCount, children.filter { $0.statusDot == .running }.count),
                    workdir: parent.workdir,
                    children: children,
                    model: itemModel
                )
            )
        }
        return results
    }

    /// 현재 메모리 캐시를 이용해 0ms로 트리를 합성한다. 캐시가 없으면 baseAgents를 즉시 반환.
    public func cachedTree(baseAgents: [UnifiedBarItem]) -> [UnifiedBarItem] {
        if let cached = cachedResult() {
            return scanTree(baseAgents: baseAgents, scanResult: cached)
        }
        return baseAgents
    }

    /// 백그라운드 태스크에서 비동기로 트리를 합성하여 UI 블로킹을 원천 차단한다.
    public func scanTreeAsync(
        baseAgents: [UnifiedBarItem],
        forceRefresh: Bool = false
    ) async -> [UnifiedBarItem] {
        let scanRes = await scanAsync(forceRefresh: forceRefresh)
        return scanTree(baseAgents: baseAgents, scanResult: scanRes)
    }

    private func extractPIDFromItemID(_ itemId: String) -> Int32? {
        let rawPidStr = itemId
            .replacingOccurrences(of: "agent-", with: "")
            .replacingOccurrences(of: "leased-", with: "")
            .replacingOccurrences(of: "room-", with: "")
        return Int32(rawPidStr)
    }

    public static func convertSubagentsToBarItems(
        _ subagents: [HostAgentProcess],
        parentIdPrefix: String
    ) -> [UnifiedBarItem] {
        return subagents.map { sub in
            let childItems = convertSubagentsToBarItems(sub.subagents, parentIdPrefix: "\(parentIdPrefix)-sub-\(sub.pid)")
            let statusDot = barStatusDot(for: sub.status)

            let displayTitle: String
            if let title = sub.title, !title.isEmpty {
                displayTitle = title
            } else {
                displayTitle = HostAgentTitleExtractor.extractSubagentTitle(command: sub.command, cwd: sub.cwd)
            }

            let modelSuffix = sub.model.map { " [\($0)]" } ?? ""
            let pidSuffix = sub.pid > 0 ? " #\(sub.pid)" : ""
            let displaySubtitle = "\(sub.tool)\(modelSuffix)\(pidSuffix)"
            let subIdSuffix = sub.pid > 0 ? String(sub.pid) : "\(sub.tool)-\(abs((sub.title ?? sub.command).hashValue))"

            return UnifiedBarItem(
                id: "\(parentIdPrefix)-sub-\(subIdSuffix)",
                title: displayTitle,
                subtitle: displaySubtitle,
                icon: .symbol("arrow.turn.down.right"),
                statusDot: statusDot,
                badge: nil,
                subjobCount: max(sub.subjobCount, childItems.count),
                runningSubjobCount: max(sub.runningSubjobCount, childItems.filter { $0.statusDot == .running }.count),
                workdir: sub.cwd,
                children: childItems,
                model: sub.model
            )
        }
    }

    private static func barStatusDot(for status: String) -> BarStatusDot {
        switch status.lowercased() {
        case "idle": return .idle
        case "waiting": return .waiting
        case "error": return .error
        case "done": return .none
        default: return .running
        }
    }

    public func attributedAgents(
        forTerminal isTerminal: Bool,
        baseAgents: [UnifiedBarItem]
    ) -> [UnifiedBarItem] {
        guard isTerminal else { return [] }
        return cachedTree(baseAgents: baseAgents)
    }
}
