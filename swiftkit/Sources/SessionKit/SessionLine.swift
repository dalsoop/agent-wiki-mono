import Foundation

/// Read the head of a transcript cheaply (list views only need cwd + first
/// prompt, not the whole file) and decode individual JSONL lines. Mirrors the
/// `FileHandle.read(upToCount:)` + `JSONSerialization` idiom repeated in four apps.
public enum SessionHead {
    /// First `cap` bytes of a file as UTF-8 (lossy). Default 64 KB — enough for
    /// session_meta / the first user message.
    public static func read(_ url: URL, cap: Int = 64 * 1024) -> String {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? fh.close() }
        let data = (try? fh.read(upToCount: cap)) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    /// Split transcript text into non-empty JSONL lines.
    public static func lines(_ text: String) -> [Substring] {
        text.split(separator: "\n").filter { !$0.isEmpty }
    }
}

/// A decoded JSONL line as a loose dictionary, with codex payload unwrapping.
/// (token-bar uses strict Codable for its needs; the other apps all use this
/// `[String: Any]` form — that's what SessionKit standardizes.)
public enum SessionLine {
    public static func decode<S: StringProtocol>(_ line: S) -> [String: Any]? {
        guard let data = String(line).data(using: .utf8) else { return nil }
        do {
            return try JSONSerialization.jsonObject(with: data) as? [String: Any]
        } catch {
            return nil
        }
    }

    /// codex wraps content under `payload` (either at top level or under
    /// `response_item`). Returns the effective payload dict for a codex line.
    public static func codexPayload(_ obj: [String: Any]) -> [String: Any]? {
        if let p = obj["payload"] as? [String: Any] { return p }
        if let ri = obj["response_item"] as? [String: Any],
           let p = ri["payload"] as? [String: Any] { return p }
        return nil
    }

    /// Grok persists ACP notifications as
    /// `{timestamp, method, params:{sessionId, update:{sessionUpdate,…}}}`.
    public static func grokUpdate(_ obj: [String: Any]) -> [String: Any]? {
        guard let method = obj["method"] as? String,
              method == "session/update" || method == "_x.ai/session/update",
              let params = obj["params"] as? [String: Any] else { return nil }
        return params["update"] as? [String: Any]
    }
}
