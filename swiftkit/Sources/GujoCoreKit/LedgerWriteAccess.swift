import Foundation

/// Who may persist `~/Library/Application Support/Gujo/`.
/// Cloud Apps is the sole writer. Gujo.app is a retired reader.
public enum LedgerWriteAccess: String, Sendable, Equatable {
    case cloudApps
    case retiredReader

    public var allowsWrite: Bool {
        switch self {
        case .cloudApps: return true
        case .retiredReader: return false
        }
    }
}

public enum LedgerWriteDenied: Error, Equatable, LocalizedError {
    case retiredOwner

    public var errorDescription: String? {
        "Gujo.app no longer writes ~/Library/Application Support/Gujo/; Gujo Cloud Apps owns the ledger."
    }
}
