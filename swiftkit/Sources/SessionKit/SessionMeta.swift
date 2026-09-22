import Foundation

/// Head-level metadata extraction — the cheap "what session is this" pull that
/// list/summary views need. Consolidates parseClaudeHead / parseCodexMeta /
/// parseCodexIndex, which agent-deck and mcp-manager implemented separately.
public enum SessionMeta {

    public struct Claude: Sendable, Equatable { public var cwd: String?; public var firstPrompt: String? }
    public struct Codex: Sendable, Equatable {
        public var cwd: String?; public var id: String?
        public var parentThreadID: String?; public var nickname: String?
    }
    public struct Grok: Sendable, Equatable {
        public var id: String?
        public var cwd: String?
        public var title: String?
        public var summary: String?
        public var modelID: String?
        public var createdAt: Date?
        public var updatedAt: Date?
        public var parentSessionID: String?
        public var agentName: String?
    }

    public struct Antigravity: Sendable, Equatable {
        public var id: String?
        public var cwd: String?
        public var title: String?
        public var preview: String?
        public var stepCount: Int?
        public var modifiedAt: Date?
        public var parentConversationID: String?
        public var agentName: String?
        public var killed: Bool
    }

    /// Antigravity summaries db 의 datetime 텍스트(`2026-09-01 12:47:23.036224+00:00`) 파싱.
    /// ISO8601 이 아니라(공백 구분·마이크로초) 전용 포매터가 필요하다. 영원값
    /// `0001-01-01` 은 "아직 입력 없음"이므로 nil 로 돌린다.
    public static func antigravityDate(_ raw: String?) -> Date? {
        guard let raw, !raw.hasPrefix("0001-01-01") else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSSXXXX"
        if let date = formatter.date(from: raw) { return date }
        // 마이크로초가 없는 변형도 받는다.
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ssXXXX"
        return formatter.date(from: raw)
    }

    /// `["file:///Users/…"]` 형태의 workspace_uris 텍스트 → 첫 번째 로컬 경로.
    public static func antigravityCWD(fromWorkspaceURIs raw: String?) -> String? {
        guard let raw, let data = raw.data(using: .utf8) else { return nil }
        let uris: [String]
        do {
            uris = (try JSONSerialization.jsonObject(with: data) as? [String]) ?? []
        } catch {
            return nil
        }
        guard let uri = uris.first(where: { $0.hasPrefix("file://") }) else { return nil }
        return String(uri.dropFirst("file://".count)).removingPercentEncoding
    }

    /// From a claude transcript head: first non-empty `cwd` and first user
    /// message text (after `cleanRules` noise-stripping). `cleanRules` is injected
    /// because each app's noise set differs — pass `SessionText.defaultNoise` or
    /// your own.
    public static func claude(head: String, clean: (Any?) -> String? = { SessionText.cleanUserText($0) }) -> Claude {
        var cwd: String?; var prompt: String?
        for line in SessionHead.lines(head) {
            guard let d = SessionLine.decode(line) else { continue }
            if cwd == nil, let c = d["cwd"] as? String, !c.isEmpty { cwd = c }
            if prompt == nil, d["type"] as? String == "user",
               let msg = d["message"] as? [String: Any], let t = clean(msg["content"]) { prompt = t }
            if cwd != nil && prompt != nil { break }
        }
        return Claude(cwd: cwd, firstPrompt: prompt)
    }

    /// From a codex rollout head: `session_meta.payload` cwd/id + subagent lineage.
    public static func codex(head: String) -> Codex {
        for line in SessionHead.lines(head) {
            guard let d = SessionLine.decode(line),
                  d["type"] as? String == "session_meta",
                  let p = d["payload"] as? [String: Any] else { continue }
            return Codex(cwd: p["cwd"] as? String, id: p["id"] as? String,
                         parentThreadID: p["parent_thread_id"] as? String,
                         nickname: p["agent_nickname"] as? String)
        }
        return Codex(cwd: nil, id: nil, parentThreadID: nil, nickname: nil)
    }

    /// `session_index.jsonl` text → [id: thread_name].
    public static func codexIndex(text: String) -> [String: String] {
        var map: [String: String] = [:]
        for line in SessionHead.lines(text) {
            guard let d = SessionLine.decode(line), let id = d["id"] as? String,
                  let name = d["thread_name"] as? String else { continue }
            map[id] = name
        }
        return map
    }

    /// First real user message from a Codex rollout head.
    public static func codexFirstPrompt(head: String) -> String? {
        for line in SessionHead.lines(head) {
            guard let obj = SessionLine.decode(line),
                  let payload = SessionLine.codexPayload(obj) else { continue }
            let type = payload["type"] as? String
            if type == "user_message", let text = SessionText.cleanUserText(payload["message"]) {
                return text
            }
            if type == "message", payload["role"] as? String == "user",
               let content = payload["content"] as? [[String: Any]],
               let text = SessionText.cleanUserText(content) { return text }
        }
        return nil
    }

    /// Grok `summary.json` metadata. The nested `info` object owns id/cwd.
    public static func grok(summary text: String) -> Grok? {
        guard let data = text.data(using: .utf8) else { return nil }
        let obj: [String: Any]
        do {
            guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            obj = parsed
        } catch {
            return nil
        }
        let info = obj["info"] as? [String: Any] ?? [:]
        return Grok(
            id: info["id"] as? String,
            cwd: info["cwd"] as? String,
            title: nonEmpty(obj["generated_title"] as? String),
            summary: nonEmpty(obj["session_summary"] as? String),
            modelID: obj["current_model_id"] as? String,
            createdAt: SessionTime.parse(obj["created_at"] as? String),
            updatedAt: SessionTime.parse((obj["last_active_at"] as? String) ?? (obj["updated_at"] as? String)),
            parentSessionID: (info["parent_session_id"] as? String) ?? (obj["parent_session_id"] as? String),
            agentName: nonEmpty(obj["agent_name"] as? String)
        )
    }

    /// First user chunk from Grok's authoritative ACP update stream.
    public static func grokFirstPrompt(head: String) -> String? {
        for line in SessionHead.lines(head) {
            guard let obj = SessionLine.decode(line),
                  let update = SessionLine.grokUpdate(obj),
                  update["sessionUpdate"] as? String == "user_message_chunk",
                  let content = update["content"] as? [String: Any],
                  let text = SessionText.cleanUserText(content["text"]) else { continue }
            return text
        }
        return nil
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}

/// User-text cleanup with an injectable noise ruleset — each app strips slightly
/// different prefixes (system-reminder tags, injection signatures, Caveat:), so
/// the rules are data, not baked in. Handles both String and `[{type:text}]`
/// content shapes.
public enum SessionText {
    /// Flatten claude `message.content` (String or block array) to plain text.
    public static func flatten(_ content: Any?) -> String? {
        if let s = content as? String { return s }
        if let blocks = content as? [[String: Any]] {
            let text = blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
                .joined(separator: "\n")
            return text.isEmpty ? nil : text
        }
        return nil
    }

    /// Default noise: drop lines that are pure tool-result/system-reminder noise
    /// and trim. Apps needing more (token-bar's injectionSignatures) pass their own.
    public static func cleanUserText(_ content: Any?, noisePrefixes: [String] = defaultNoise) -> String? {
        guard var s = flatten(content)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty
        else { return nil }
        for p in noisePrefixes where s.hasPrefix(p) { return nil }
        // strip a leading <system-reminder>…</system-reminder> if present
        if s.hasPrefix("<"), let end = s.range(of: ">") { s.removeSubrange(s.startIndex..<end.upperBound) }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }

    public static let defaultNoise = ["Caveat:", "[Request interrupted", "<system-reminder>"]
}
