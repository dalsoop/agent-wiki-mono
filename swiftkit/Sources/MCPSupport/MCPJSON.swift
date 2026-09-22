import Foundation

/// JSON serialization that never crashes the server.
public enum MCPJSON {
    /// Serialize to JSON `Data`, returning `nil` instead of crashing.
    ///
    /// `JSONSerialization.data(withJSONObject:)` raises an *Objective-C exception*
    /// (not a Swift `Error`) for non-finite numbers (NaN/Infinity) — `try?` cannot
    /// catch it, so it would abort the process. Guarding with `isValidJSONObject`
    /// first makes the path exception-free.
    public static func data(_ object: Any,
                            options: JSONSerialization.WritingOptions = []) -> Data? {
        guard JSONSerialization.isValidJSONObject(object) else { return nil }
        do {
            return try JSONSerialization.data(withJSONObject: object, options: options)
        } catch {
            return nil
        }
    }

    /// Serialize to a JSON `String` for tool text content; on failure returns a
    /// valid JSON error string rather than silently producing `{}`.
    public static func string(_ object: Any,
                              options: JSONSerialization.WritingOptions = [.sortedKeys]) -> String {
        guard let data = data(object, options: options),
              let s = String(data: data, encoding: .utf8) else {
            return "{\"error\":\"value not serializable to JSON\"}"
        }
        return s
    }
}
