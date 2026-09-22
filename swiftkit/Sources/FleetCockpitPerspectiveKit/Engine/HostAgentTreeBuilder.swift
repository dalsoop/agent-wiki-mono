import Foundation

/// 프로세스 테이블 파싱 및 스캔 결과 조합 총괄 빌더
public enum HostAgentTreeBuilder: Sendable {

    // MARK: - 프로세스 테이블 파싱
    public static func parseProcessTable(_ raw: String) -> [ProcessRecord] {
        var records: [ProcessRecord] = []
        let lines = raw.split(separator: "\n", omittingEmptySubsequences: true)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let isPidHeader = trimmed.hasPrefix("PID")
            let isPpidHeader = trimmed.contains("PPID") && trimmed.contains("COMMAND")
            if isPidHeader || isPpidHeader {
                continue
            }

            let parts = trimmed.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard parts.count >= 4 else { continue }
            guard let pid = Int32(parts[0]), let ppid = Int32(parts[1]) else { continue }

            let ttyRaw = String(parts[2])
            let isNoTTY = (ttyRaw == "??" || ttyRaw == "-")
            let tty: String? = isNoTTY ? nil : ttyRaw
            let command = String(parts[3]).trimmingCharacters(in: .whitespacesAndNewlines)

            records.append(ProcessRecord(pid: pid, ppid: ppid, tty: tty, command: command))
        }
        return records
    }

    public static func detectRole(_ command: String) -> ProcessRole {
        HostAgentLineageExtractor.detectRole(command)
    }

    // MARK: - 프로세스 트리 계층 빌드 (AgentTreeNode)
    public static func buildTree(from records: [ProcessRecord]) -> [AgentTreeNode] {
        let recordMap = Dictionary(uniqueKeysWithValues: records.map { ($0.pid, $0) })
        let childrenMap = Dictionary(grouping: records, by: \.ppid)

        func buildNode(record: ProcessRecord, isDescendantOfAgent: Bool) -> AgentTreeNode {
            var role = detectRole(record.command)
            if isDescendantOfAgent {
                role = .subagent
            }
            let isAgent = (role == .claude || role == .agy || role == .codex || role == .grok || role == .glm)
            let childRecords = childrenMap[record.pid] ?? []
            let childNodes = childRecords.map { buildNode(record: $0, isDescendantOfAgent: isDescendantOfAgent || isAgent) }
            return AgentTreeNode(
                pid: record.pid,
                ppid: record.ppid,
                command: record.command,
                role: role,
                children: childNodes
            )
        }

        let rootRecords = records.filter { recordMap[$0.ppid] == nil }
        return rootRecords.map { buildNode(record: $0, isDescendantOfAgent: false) }
    }

    // MARK: - 계통 추적 (Lineage Extraction)
    public static func extractLineages(from records: [ProcessRecord]) -> [AgentLineage] {
        let recordMap = Dictionary(uniqueKeysWithValues: records.map { ($0.pid, $0) })
        let childrenMap = Dictionary(grouping: records, by: \.ppid)
        let roots = findRootPIDs(records: records)
        let mainAgentPIDs = HostAgentLineageExtractor.findMainAgentPIDs(in: records, recordMap: recordMap)

        var lineages: [AgentLineage] = []
        for agentPID in mainAgentPIDs {
            let ptyAndTmux = HostAgentLineageExtractor.traceAncestors(for: agentPID, recordMap: recordMap)
            var subPIDs: [Int32] = []
            HostAgentLineageExtractor.collectSubagents(ppid: agentPID, childrenMap: childrenMap, into: &subPIDs)

            lineages.append(
                AgentLineage(
                    claudePID: agentPID,
                    ptyPID: ptyAndTmux.ptyPID,
                    tmuxPID: ptyAndTmux.tmuxPID,
                    herdrPID: roots.herdrServerPID,
                    ghosttyPID: roots.ghosttyPID,
                    subagentPIDs: subPIDs
                )
            )
        }
        return lineages
    }

    // MARK: - 계통 컨텍스트 구조체
    public struct LineageContext: Sendable {
        public let lineage: AgentLineage
        public let agentRecord: ProcessRecord
        public let toolName: String
        public var cwd: String?
        public let tokens: [String]
        public let sessionID: String?
        public var matchedPaneIndex: Int?
    }

    // MARK: - 스캔 결과 빌드
    public static func buildScanResult(
        records: [ProcessRecord],
        lineages: [AgentLineage],
        cwdMap: [Int32: String],
        herdrJson: String?
    ) -> HostAgentTreeScanResult {
        let herdrPanes = parseHerdrPanes(from: herdrJson)
        let roots = findRootPIDs(records: records)
        let recordMap = Dictionary(uniqueKeysWithValues: records.map { ($0.pid, $0) })
        let childrenMap = Dictionary(grouping: records, by: \.ppid)

        var contexts = prepareContexts(lineages: lineages, recordMap: recordMap, cwdMap: cwdMap)
        var usedPaneIDs = Set<String>()

        // HostAgentTreeMatcher를 통한 3단계 매칭
        HostAgentTreeMatcher.matchPass0ByProcessIDs(contexts: &contexts, herdrPanes: herdrPanes, usedPaneIDs: &usedPaneIDs)
        HostAgentTreeMatcher.matchPass1BySessionID(contexts: &contexts, herdrPanes: herdrPanes, usedPaneIDs: &usedPaneIDs)
        HostAgentTreeMatcher.matchPass2ByCWDAndHeuristics(contexts: &contexts, herdrPanes: herdrPanes, usedPaneIDs: &usedPaneIDs)

        var finalAgents: [HostAgentProcess] = []
        for ctx in contexts {
            let agent = HostAgentTreeMatcher.buildHostAgentProcess(
                ctx: ctx,
                herdrPanes: herdrPanes,
                childrenMap: childrenMap,
                cwdMap: cwdMap
            )
            finalAgents.append(agent)
        }

        return HostAgentTreeScanResult(
            agents: finalAgents,
            lineages: lineages,
            totalAgentCount: finalAgents.count,
            ghosttyPID: roots.ghosttyPID,
            herdrServerPID: roots.herdrServerPID
        )
    }

    private static func parseHerdrPanes(from json: String?) -> [HerdrPane] {
        guard let json, let data = json.data(using: .utf8) else { return [] }
        do {
            let decoded = try JSONDecoder().decode(HerdrPaneResponse.self, from: data)
            return decoded.result?.panes ?? []
        } catch {
            return []
        }
    }

    private static func findRootPIDs(records: [ProcessRecord]) -> (ghosttyPID: Int32?, herdrServerPID: Int32?) {
        var ghosttyPID: Int32?
        var herdrServerPID: Int32?
        for r in records {
            if ghosttyPID == nil && r.command.lowercased().contains("ghostty") && r.ppid == 1 {
                ghosttyPID = r.pid
            }
            let isHerdr = r.command.lowercased().contains("herdr server") || r.command.lowercased().hasPrefix("herdr")
            if herdrServerPID == nil && isHerdr {
                herdrServerPID = r.pid
            }
        }
        return (ghosttyPID, herdrServerPID)
    }

    private static func prepareContexts(
        lineages: [AgentLineage],
        recordMap: [Int32: ProcessRecord],
        cwdMap: [Int32: String]
    ) -> [LineageContext] {
        var contexts: [LineageContext] = []
        for lineage in lineages {
            guard let agentRecord = recordMap[lineage.claudePID] else { continue }
            let role = detectRole(agentRecord.command)
            let toolName = role == .other ? "agent" : role.rawValue

            var cwd = cwdMap[lineage.claudePID]
            let tokens = agentRecord.command.split(separator: " ").map(String.init)
            if cwd == nil {
                cwd = extractCWDFromTokens(tokens)
            }
            let sessionID = extractResumeSessionID(from: tokens)

            contexts.append(
                LineageContext(
                    lineage: lineage,
                    agentRecord: agentRecord,
                    toolName: toolName,
                    cwd: cwd,
                    tokens: tokens,
                    sessionID: sessionID,
                    matchedPaneIndex: nil
                )
            )
        }
        return contexts
    }

    private static func extractCWDFromTokens(_ tokens: [String]) -> String? {
        for i in 0..<tokens.count {
            let tok = tokens[i]
            let isFlag = (tok == "--add-dir" || tok == "--workdir" || tok == "-C")
            guard isFlag, i + 1 < tokens.count else { continue }
            let candidate = tokens[i + 1]
            if candidate.hasPrefix("/") || candidate.hasPrefix("~") {
                return candidate
            }
        }
        return nil
    }

    private static func extractResumeSessionID(from tokens: [String]) -> String? {
        for i in 0..<tokens.count {
            if tokens[i] == "--resume", i + 1 < tokens.count {
                return tokens[i + 1]
            }
        }
        return nil
    }
}
