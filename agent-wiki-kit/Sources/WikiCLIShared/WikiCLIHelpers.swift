import Foundation

/// Default agent identifier — resolves from environment or falls back to "agent:local".
public func defaultAgentID() -> String {
    ProcessInfo.processInfo.environment["CITATION_ACTOR"]
        ?? ProcessInfo.processInfo.environment["MEMO_LEDGER_AUTHOR"]
        ?? "agent:local"
}
