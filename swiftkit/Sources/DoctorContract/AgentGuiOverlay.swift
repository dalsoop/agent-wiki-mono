import Foundation

/// WindowServer compositor pressure from **Orca overlay · SkyComputer Use only**.
/// Seat IDEs (Cursor / Claude / Codex / Grok / Chrome / Electron) are not counted.
/// Host Doctor and Work Monitor both call this — do not copy the classifier.
public enum AgentGuiOverlay: Sendable {
    /// Orca family max (10) + a little Computer Use before WARN. Seat-era default was 50.
    public static let defaultSoftCap = 12

    public static let familyCap: [String: Int] = [
        "Orca": 10,
        "SkyComputer": 12,
    ]

    /// Family caps summed — a stored cap above this can never fire.
    public static var theoreticalMaxWeight: Int {
        familyCap.values.reduce(0, +)
    }

    /// Built-in defaults from the old "agent GUI seats" era.
    public static func isSeatEraDefaultCap(_ n: Int) -> Bool {
        n == 25 || n == 50
    }

    /// Cap that cannot produce `agent_gui_over_cap` (seat-era 25/50, or above overlay max).
    public static func isDeadCap(_ n: Int) -> Bool {
        isSeatEraDefaultCap(n) || n > theoreticalMaxWeight
    }

    public static func usableCap(_ n: Int) -> Int {
        isDeadCap(n) ? defaultSoftCap : max(1, n)
    }

    public static func normalizedCap(_ n: Int) -> Int { usableCap(n) }

    public static func classify(_ comm: String) -> String? {
        let lower = comm.lowercased()
        if lower.contains("skycomputer") { return "SkyComputer" }
        let looksGui = lower.contains(".app/")
            || lower.contains("helper")
            || lower.contains("renderer")
            || lower.contains("framework")
        if !looksGui { return nil }
        if lower.contains("crashpad") { return nil }
        if lower.contains("agentorcadoctor") || lower.contains("agent orca doctor") { return nil }
        if lower.contains("chrome-native-host") { return nil }
        if lower.contains("cursor") { return nil }
        if lower.contains("visual studio code") || lower.contains("code helper") { return nil }
        if lower.contains("claude") { return nil }
        if lower.contains("chatgpt") || lower.contains("codex") { return nil }
        if lower.contains("grok") { return nil }
        if lower.contains("google chrome") { return nil }
        if lower.contains("electron") { return nil }
        if lower.contains("orca") { return "Orca" }
        return nil
    }

    public static func weight<S: Sequence>(commands: S) -> (total: Int, byFamily: [String: Int])
    where S.Element == String {
        var raw: [String: Int] = [:]
        for comm in commands {
            guard let family = classify(comm) else { continue }
            raw[family, default: 0] += 1
        }
        var weighted: [String: Int] = [:]
        for (k, v) in raw {
            weighted[k] = min(v, familyCap[k] ?? 10)
        }
        return (weighted.values.reduce(0, +), weighted)
    }
}
