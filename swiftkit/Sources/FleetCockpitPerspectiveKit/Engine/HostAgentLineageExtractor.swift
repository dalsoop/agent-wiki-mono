import Foundation

/// 프로세스 역할 판별 및 조상/계통 추적 전담 엔진
public enum HostAgentLineageExtractor: Sendable {

    private static let transientBins: Set<String> = [
        "git", "ps", "lsof", "cat", "grep", "rg", "swift", "swift-frontend",
        "sed", "awk", "find", "head", "tail", "curl", "tar", "zip"
    ]

    private static let helperPatterns: [String] = [
        ".app/contents/macos/", ".app/contents/frameworks/",
        "helper (renderer)", "helper (gpu)", "helper (plugin)", "helper (alerts)",
        "--type=renderer", "--type=gpu-process", "--type=utility", "--type=crashpad-handler",
        "crashpad_handler", "networkservice"
    ]

    public static func isAppOrHelperProcess(_ command: String) -> Bool {
        let lower = command.lowercased()
        for pattern in helperPatterns where lower.contains(pattern) {
            return true
        }
        return false
    }

    private static func extractQuotedPath(_ command: String) -> (path: String, args: [String])? {
        guard let first = command.first, first == "\"" || first == "'" else { return nil }
        let quote = first
        let withoutFirst = command.dropFirst()
        guard let quoteEnd = withoutFirst.firstIndex(of: quote) else { return nil }
        let exe = String(withoutFirst[..<quoteEnd])
        let rest = String(withoutFirst[withoutFirst.index(after: quoteEnd)...]).trimmingCharacters(in: .whitespaces)
        let args = rest.split(separator: " ").map(String.init)
        return (exe, args)
    }

    private static func extractSpacedPath(_ first: String, tokens: [String]) -> (path: String, args: [String])? {
        guard first.hasPrefix("/") else { return nil }
        var candidate = first
        for i in 1..<tokens.count {
            if FileManager.default.fileExists(atPath: candidate) {
                return (candidate, Array(tokens[i...]))
            }
            candidate += " " + tokens[i]
        }
        if FileManager.default.fileExists(atPath: candidate) {
            return (candidate, [])
        }
        return nil
    }

    public static func extractExecutablePath(_ command: String) -> (path: String, args: [String]) {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ("", []) }

        if let quoted = extractQuotedPath(trimmed) {
            return quoted
        }

        let tokens = trimmed.split(separator: " ").map(String.init)
        guard let first = tokens.first else { return ("", []) }

        if let spaced = extractSpacedPath(first, tokens: tokens) {
            return spaced
        }

        return (first, Array(tokens.dropFirst()))
    }

    private static let ignoredBinSubstrings: [String] = ["bot", "helper", "renderer"]

    public static func detectRole(_ command: String) -> ProcessRole {
        guard !isAppOrHelperProcess(command) else { return .other }

        let (exePath, tokens) = extractExecutablePath(command)
        var clean = exePath
        if clean.hasPrefix("-") { clean.removeFirst() }
        let bin = URL(fileURLWithPath: clean).lastPathComponent.lowercased()

        for sub in ignoredBinSubstrings where bin.contains(sub) {
            return .other
        }

        if let directRole = directRole(for: bin, command: command) {
            return directRole
        }
        return detectScriptRuntimeRole(bin: bin, tokens: tokens)
    }

    private static let ptyBins: Set<String> = ["zsh", "bash", "sh", "login"]
    private static let scriptRuntimes: Set<String> = ["node", "python", "bun", "deno"]

    private static func directRole(for bin: String, command: String) -> ProcessRole? {
        switch bin {
        case "herdr": return .herdr
        case "tmux": return .tmux
        case "claude", "claude-code": return .claude
        case "agy", "antigravity": return .agy
        case "codex": return .codex
        case "grok": return .grok
        case "glm": return .glm
        default:
            if command.contains("tmux:") { return .tmux }
            if ptyBins.contains(bin) { return .pty }
            return nil
        }
    }

    private static let subtokenRoleKeywords: [(String, ProcessRole)] = [
        ("claude", .claude),
        ("agy", .agy),
        ("codex", .codex),
        ("grok", .grok),
        ("glm", .glm),
        ("subagent", .subagent),
        ("worker", .subagent),
    ]

    private static let primaryAgentRoles: Set<ProcessRole> = [.claude, .agy, .codex, .grok, .glm]
    private static let parentAgentRoles: Set<ProcessRole> = [.claude, .agy, .codex, .grok, .glm, .subagent]

    private static func detectScriptRuntimeRole(bin: String, tokens: [String]) -> ProcessRole {
        guard scriptRuntimes.contains(bin) else { return .other }

        for tok in tokens {
            let sub = URL(fileURLWithPath: tok).lastPathComponent.lowercased()
            let matched = subtokenRoleKeywords.first { sub.contains($0.0) }
            guard let match = matched else { continue }
            return match.1
        }
        return .other
    }

    public static func findMainAgentPIDs(in records: [ProcessRecord], recordMap: [Int32: ProcessRecord]) -> [Int32] {
        var agentPIDs: [Int32] = []
        for r in records {
            if isAppOrHelperProcess(r.command) { continue }

            let role = detectRole(r.command)
            guard primaryAgentRoles.contains(role) else { continue }

            var curr = r.ppid
            var isSubagent = false
            for _ in 0..<15 {
                guard let parent = recordMap[curr] else { break }
                let parentRole = detectRole(parent.command)
                if parentAgentRoles.contains(parentRole) {
                    isSubagent = true
                    break
                }
                curr = parent.ppid
            }
            guard !isSubagent else { continue }
            agentPIDs.append(r.pid)
        }
        return agentPIDs
    }

    public static func traceAncestors(for agentPID: Int32, recordMap: [Int32: ProcessRecord]) -> (ptyPID: Int32?, tmuxPID: Int32?) {
        var currentPID = agentPID
        var ptyPID: Int32?
        var tmuxPID: Int32?

        for _ in 0..<10 {
            guard let a = recordMap[currentPID], let parent = recordMap[a.ppid] else { break }
            let role = detectRole(parent.command)

            let isPtyMatch = (role == .pty) || (a.tty != nil)
            if ptyPID == nil && isPtyMatch {
                ptyPID = parent.pid
            }
            let isMultiplexer = (role == .tmux || role == .herdr)
            if tmuxPID == nil && isMultiplexer {
                tmuxPID = parent.pid
            }
            currentPID = parent.pid
        }
        return (ptyPID, tmuxPID)
    }

    public static func collectSubagents(
        ppid: Int32,
        childrenMap: [Int32: [ProcessRecord]],
        into subPIDs: inout [Int32]
    ) {
        guard let kids = childrenMap[ppid] else { return }
        for kid in kids {
            if isAppOrHelperProcess(kid.command) { continue }

            let (exe, _) = extractExecutablePath(kid.command)
            let cleanBin = URL(fileURLWithPath: exe).lastPathComponent.lowercased()
            if transientBins.contains(cleanBin) { continue }

            let role = detectRole(kid.command)
            let isInteractivePty = (role == .pty && kid.tty != nil && !kid.command.contains("-c"))
            guard !isInteractivePty && role != .herdr && role != .tmux else { continue }

            subPIDs.append(kid.pid)
            collectSubagents(ppid: kid.pid, childrenMap: childrenMap, into: &subPIDs)
        }
        subPIDs.sort()
    }
}
