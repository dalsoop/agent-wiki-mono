import Foundation

/// Field-extraction helpers that every app re-derives identically: project name
/// from a cwd (bare-worktree convention), MCP server from a tool name, codex
/// UUID from a rollout filename, and flexible ISO-8601 parsing.
public enum SessionIdent {
    /// cwd → human project name, honoring the bare-worktree layout: a trailing
    /// `main` / `wt-*` / `feat-*` segment is prefixed with its parent so
    /// `.../swift-app-mono/main` reads as `swift-app-mono/main`. Verbatim from the
    /// rule shared by agent-session-replay and agent-fleet-map.
    public static func projectName(cwd: String) -> String {
        let comps = (cwd as NSString).pathComponents.filter { $0 != "/" }
        guard let last = comps.last else { return cwd }
        if (last == "main" || last.hasPrefix("wt-") || last.hasPrefix("feat-")), comps.count >= 2 {
            return "\(comps[comps.count - 2])/\(last)"
        }
        return last
    }

    /// `mcp__<server>__<tool>` → `<server>` (nil if not an MCP tool name).
    public static func mcpServer(fromToolName name: String) -> String? {
        guard name.hasPrefix("mcp__") else { return nil }
        return String(name.dropFirst(5)).components(separatedBy: "__").first
    }

    /// Extract the trailing UUID from a codex `rollout-...-<uuid>.jsonl` filename.
    public static func codexUUID(fromFileName file: String) -> String? {
        let stem = (file as NSString).deletingPathExtension
        let parts = stem.components(separatedBy: "-")
        guard parts.count >= 5 else { return nil }
        let candidate = parts.suffix(5).joined(separator: "-")
        return isUUID(candidate) ? candidate.lowercased() : nil
    }

    static func isUUID(_ s: String) -> Bool { UUID(uuidString: s) != nil }

    /// First whitespace-delimited token of a shell command (for grouping exec
    /// nodes by program). Strips a leading path so `/bin/ls` → `ls`.
    public static func commandHead(_ cmd: String) -> String {
        let first = cmd.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).first.map(String.init) ?? cmd
        return (first as NSString).lastPathComponent
    }
}

/// Lenient ISO-8601 parsing: try fractional seconds first, then plain. The exact
/// two-step fallback copied in four files.
public enum SessionTime {
    public static func parse(_ s: String?) -> Date? {
        guard let s else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    /// Unix seconds used by Grok `updates.jsonl`.
    public static func parseUnix(_ value: Any?) -> Date? {
        if let seconds = value as? Double { return Date(timeIntervalSince1970: seconds) }
        if let seconds = value as? Int { return Date(timeIntervalSince1970: Double(seconds)) }
        if let seconds = value as? NSNumber { return Date(timeIntervalSince1970: seconds.doubleValue) }
        return nil
    }
}
