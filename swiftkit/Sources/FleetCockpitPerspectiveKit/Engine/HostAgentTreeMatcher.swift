import Foundation
import StateRootKit

/// Herdr Pane과 프로세스 계통 간의 다중 패스(Multi-Pass) 매칭 엔진
public enum HostAgentTreeMatcher: Sendable {

    // MARK: - Pass 0: 프로세스 ID/쉘 PID 직속 일치
    public static func matchPass0ByProcessIDs(
        contexts: inout [HostAgentTreeBuilder.LineageContext],
        herdrPanes: [HerdrPane],
        usedPaneIDs: inout Set<String>
    ) {
        for i in 0..<contexts.count {
            let ctx = contexts[i]
            for (pIdx, pane) in herdrPanes.enumerated() {
                if let paneID = pane.pane_id, usedPaneIDs.contains(paneID) { continue }

                let matchesFgPgid = (pane.foreground_process_group_id != nil && pane.foreground_process_group_id == ctx.lineage.claudePID)
                let matchesShellPid = (pane.shell_pid != nil && pane.shell_pid == ctx.lineage.ptyPID)
                let matchesFgPids = pane.foreground_pids?.contains(ctx.lineage.claudePID) ?? false
                let isMatched = matchesFgPgid || matchesShellPid || matchesFgPids

                guard isMatched else { continue }
                contexts[i].matchedPaneIndex = pIdx
                if let paneID = pane.pane_id { usedPaneIDs.insert(paneID) }
                break
            }
        }
    }

    // MARK: - Pass 1: 세션 ID 일치
    public static func matchPass1BySessionID(
        contexts: inout [HostAgentTreeBuilder.LineageContext],
        herdrPanes: [HerdrPane],
        usedPaneIDs: inout Set<String>
    ) {
        for i in 0..<contexts.count {
            guard contexts[i].matchedPaneIndex == nil, let sessID = contexts[i].sessionID else { continue }
            for (pIdx, pane) in herdrPanes.enumerated() {
                if let paneID = pane.pane_id, usedPaneIDs.contains(paneID) { continue }
                guard let pSession = pane.agent_session?.value, pSession == sessID else { continue }

                contexts[i].matchedPaneIndex = pIdx
                if let paneID = pane.pane_id { usedPaneIDs.insert(paneID) }
                break
            }
        }
    }

    // MARK: - Pass 2: 잔여 CWD 및 휴리스틱 일치
    public static func matchPass2ByCWDAndHeuristics(
        contexts: inout [HostAgentTreeBuilder.LineageContext],
        herdrPanes: [HerdrPane],
        usedPaneIDs: inout Set<String>
    ) {
        for i in 0..<contexts.count {
            guard contexts[i].matchedPaneIndex == nil else { continue }
            let ctx = contexts[i]

            for (pIdx, pane) in herdrPanes.enumerated() {
                if let paneID = pane.pane_id, usedPaneIDs.contains(paneID) { continue }
                guard let pAgent = pane.agent?.lowercased(), pAgent.contains(ctx.toolName) else { continue }

                let matchesCwd = matchCWD(contextCWD: ctx.cwd, pane: pane)
                guard matchesCwd else { continue }

                contexts[i].matchedPaneIndex = pIdx
                if let paneID = pane.pane_id { usedPaneIDs.insert(paneID) }
                break
            }
        }
    }

    public static func matchCWD(contextCWD: String?, pane: HerdrPane) -> Bool {
        guard let cwd = contextCWD, !cwd.isEmpty else { return false }
        let normCwd = (cwd as NSString).standardizingPath

        if let pCwd = pane.cwd, !pCwd.isEmpty {
            let normPCwd = (pCwd as NSString).standardizingPath
            let isExactOrSub = normCwd == normPCwd || normCwd.hasPrefix(normPCwd) || normPCwd.hasPrefix(normCwd)
            if isExactOrSub { return true }
        }
        if let fgCwd = pane.foreground_cwd, !fgCwd.isEmpty {
            let normFgCwd = (fgCwd as NSString).standardizingPath
            let isExactOrSub = normCwd == normFgCwd || normCwd.hasPrefix(normFgCwd) || normFgCwd.hasPrefix(normCwd)
            if isExactOrSub { return true }
        }
        return false
    }

    // MARK: - 단일 HostAgentProcess 구성
    public static func buildHostAgentProcess(
        ctx: HostAgentTreeBuilder.LineageContext,
        herdrPanes: [HerdrPane],
        childrenMap: [Int32: [ProcessRecord]],
        cwdMap: [Int32: String]
    ) -> HostAgentProcess {
        var matchedPane: HerdrPane?
        if let idx = ctx.matchedPaneIndex, idx < herdrPanes.count {
            matchedPane = herdrPanes[idx]
        }

        let container = resolveContainer(matchedPane: matchedPane, lineage: ctx.lineage)
        let model = resolveModel(matchedPane: matchedPane, tokens: ctx.tokens)
        let resolvedTitle = resolveTitle(matchedPane: matchedPane, ctx: ctx)
        let resolvedStatus = matchedPane?.agent_status ?? "running"

        let subagents = buildSubagents(
            lineage: ctx.lineage,
            childrenMap: childrenMap,
            cwdMap: cwdMap,
            matchedPane: matchedPane,
            toolName: ctx.toolName
        )

        return HostAgentProcess(
            pid: ctx.lineage.claudePID,
            ppid: ctx.agentRecord.ppid,
            tty: ctx.agentRecord.tty,
            tool: ctx.toolName,
            command: ctx.agentRecord.command,
            arguments: Array(ctx.tokens.dropFirst()),
            cwd: ctx.cwd ?? matchedPane?.cwd,
            isSubagent: false,
            subagents: subagents,
            subjobCount: max(subagents.count, ctx.lineage.subagentPIDs.count),
            runningSubjobCount: max(subagents.filter { $0.status == "working" || $0.status == "running" }.count, ctx.lineage.subagentPIDs.count),
            sessionID: ctx.sessionID ?? matchedPane?.agent_session?.value,
            title: resolvedTitle,
            container: container,
            status: resolvedStatus,
            model: model
        )
    }

    private static func resolveContainer(matchedPane: HerdrPane?, lineage: AgentLineage) -> String {
        if matchedPane != nil { return "Ghostty" }
        if lineage.ghosttyPID != nil { return "Ghostty" }
        if lineage.tmuxPID != nil { return "tmux" }
        return "Standalone"
    }

    private static func resolveModel(matchedPane: HerdrPane?, tokens: [String]) -> String? {
        for j in 0..<tokens.count {
            let tok = tokens[j]
            let isModelFlag = (tok == "--model" || tok == "-m")
            guard isModelFlag, j + 1 < tokens.count else { continue }
            return tokens[j + 1]
        }
        return nil
    }

    private static func resolveTitle(matchedPane: HerdrPane?, ctx: HostAgentTreeBuilder.LineageContext) -> String? {
        if let raw = matchedPane?.terminal_title_stripped ?? matchedPane?.terminal_title {
            let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let isGenericShell = (clean.isEmpty || clean == "zsh" || clean == "bash")
            if !isGenericShell {
                return clean
            }
        }
        if let cwd = ctx.cwd {
            return URL(fileURLWithPath: cwd).lastPathComponent
        }
        return ctx.toolName
    }

    private static func buildSubagents(
        lineage: AgentLineage,
        childrenMap: [Int32: [ProcessRecord]],
        cwdMap: [Int32: String],
        matchedPane: HerdrPane?,
        toolName: String
    ) -> [HostAgentProcess] {
        var subagents = buildSubagentTree(
            parentPID: lineage.claudePID,
            childrenMap: childrenMap,
            cwdMap: cwdMap,
            matchedPane: matchedPane,
            toolName: toolName
        )
        let inProc = parseInProcessSubagents(paneID: matchedPane?.pane_id, sessionID: matchedPane?.agent_session?.value)
        subagents.append(contentsOf: inProc)
        return subagents
    }

    private static func buildSubagentTree(
        parentPID: Int32,
        childrenMap: [Int32: [ProcessRecord]],
        cwdMap: [Int32: String],
        matchedPane: HerdrPane?,
        toolName: String
    ) -> [HostAgentProcess] {
        guard let kids = childrenMap[parentPID] else { return [] }
        var result: [HostAgentProcess] = []
        for kid in kids {
            let role = HostAgentLineageExtractor.detectRole(kid.command)
            let isInteractivePty = (role == .pty && kid.tty != nil && !kid.command.contains("-c"))
            guard !isInteractivePty && role != .herdr && role != .tmux else { continue }

            let kidTool = (role == .other || role == .subagent) ? "subagent" : role.rawValue
            let sCwd = cwdMap[kid.pid] ?? matchedPane?.cwd
            let sTitle = HostAgentTitleExtractor.extractSubagentTitle(command: kid.command, cwd: sCwd)
            let childSubagents = buildSubagentTree(
                parentPID: kid.pid,
                childrenMap: childrenMap,
                cwdMap: cwdMap,
                matchedPane: matchedPane,
                toolName: toolName
            )
            result.append(
                HostAgentProcess(
                    pid: kid.pid,
                    ppid: parentPID,
                    tty: nil,
                    tool: kidTool,
                    command: kid.command,
                    cwd: sCwd,
                    isSubagent: true,
                    subagents: childSubagents,
                    subjobCount: childSubagents.count,
                    runningSubjobCount: childSubagents.count,
                    sessionID: nil,
                    title: sTitle,
                    container: "Ghostty",
                    status: "running",
                    model: nil
                )
            )
        }
        return result
    }

    public static func parseInProcessSubagents(paneID: String?, sessionID: String?) -> [HostAgentProcess] {
        guard let paneID, !paneID.isEmpty else { return [] }
        let deckPath = StateRootKit.hostPath(".swift-app-state/agent-deck.json")
        let deckURL = URL(fileURLWithPath: deckPath)

        // 신선도(freshness) 검증: mtime 및 contentModificationDate 확인 (stale-evidence 방지)
        do {
            let vals = try deckURL.resourceValues(forKeys: [.contentModificationDateKey])
            if let mtime = vals.contentModificationDate {
                guard Date().timeIntervalSince(mtime) < 300 else { return [] }
            }
        } catch {
            return []
        }
        guard let data = try? Data(contentsOf: deckURL) else { return [] }

        let rooms: [[String: Any]]
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let parsedRooms = json["rooms"] as? [[String: Any]] else {
                return []
            }
            rooms = parsedRooms
        } catch {
            return []
        }

        var results: [HostAgentProcess] = []
        for room in rooms {
            let occupants = room["occupants"] as? [[String: Any]] ?? []
            for occ in occupants {
                guard let subagents = occ["subagents"] as? [[String: Any]], !subagents.isEmpty else { continue }
                for sub in subagents {
                    let subName = sub["name"] as? String ?? sub["role"] as? String ?? "Subagent"
                    let subDesc = sub["description"] as? String
                    let subModel = sub["model"] as? String
                    let subPid = Int32(abs(subName.hashValue % 60000) + 10000)

                    results.append(
                        HostAgentProcess(
                            pid: subPid,
                            ppid: 0,
                            tty: nil,
                            tool: "subagent",
                            command: subDesc ?? subName,
                            cwd: nil,
                            isSubagent: true,
                            subagents: [],
                            subjobCount: 0,
                            runningSubjobCount: 0,
                            sessionID: sessionID,
                            title: subName + (subDesc != nil ? " (\(subDesc!))" : ""),
                            container: "in_process",
                            status: "working",
                            model: subModel
                        )
                    )
                }
            }
        }
        return results
    }
}
