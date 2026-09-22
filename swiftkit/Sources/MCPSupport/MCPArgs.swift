import Foundation

/// Argument coercion for MCP tool calls (JSON values arrive as `NSNumber`/`String`).
public enum MCPArgs {
    /// Coerce a JSON argument to `Int` without ever trapping.
    ///
    /// `Int(someHugeDouble)` is a *trapping* conversion — a client passing `1e308`
    /// would abort the whole server process. We instead use `Int(exactly:)` so an
    /// out-of-range or non-finite number returns `nil` (→ a clean "bad argument"
    /// error). JSON booleans (`true`/`false`) are rejected rather than coerced to 1/0.
    public static func int(_ value: Any?) -> Int? {
        if let n = value as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() { return nil }
        if let i = value as? Int { return i }
        if let d = value as? Double {
            guard d.isFinite else { return nil }
            return Int(exactly: d.rounded(.towardZero))
        }
        if let s = value as? String { return Int(s) }
        return nil
    }

    /// Coerce a JSON argument to `Double`. Rejects JSON booleans and non-finite
    /// values; accepts numbers and numeric strings.
    public static func double(_ value: Any?) -> Double? {
        if let n = value as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() { return nil }
        if let d = value as? Double { return d.isFinite ? d : nil }
        if let i = value as? Int { return Double(i) }
        if let s = value as? String, let d = Double(s) { return d.isFinite ? d : nil }
        return nil
    }

    /// Coerce a JSON argument to `Bool`. Accepts JSON booleans and the strings
    /// `"true"`/`"false"`; anything else returns `nil`.
    public static func bool(_ value: Any?) -> Bool? {
        if let b = value as? Bool { return b }
        if let n = value as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() { return n.boolValue }
        if let s = value as? String {
            if s == "true" { return true }
            if s == "false" { return false }
        }
        return nil
    }
}
