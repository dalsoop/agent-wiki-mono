import Foundation

public enum ShellQuote {
    /// POSIX single-quote wrapping safe for remote `ssh host 'cmd'`.
    public static func single(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    public static func join(_ parts: [String]) -> String {
        parts.map(single).joined(separator: " ")
    }
}
