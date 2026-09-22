import Foundation

enum TranscriptGrok {
    /// grok `-p --output-format streaming-messages-json` 한 줄.
    /// ACP `params.update.sessionUpdate` 와 최상위 키가 다르다.
    static func looksLikeStream(_ d: [String: Any]) -> Bool {
        switch d["type"] as? String {
        case "system": return d["subtype"] as? String == "init"
        case "assistant", "user", "result": return true
        default: return false
        }
    }

    /// 파일 첫 줄이 `type:system` + `subtype:init` 이면 헤드리스 스트림.
    static func isStreamingMessages(text: String) -> Bool {
        guard let first = text.split(separator: "\n", omittingEmptySubsequences: true).first,
              let d = JSONLine.object(usableLine(first)) else { return false }
        return d["type"] as? String == "system" && d["subtype"] as? String == "init"
    }

    static func ingest(
        _ d: [String: Any],
        at: Date?,
        into sink: inout TranscriptSink
    ) -> Bool {
        if looksLikeStream(d) { return ingestStream(d, at: at, into: &sink) }
        guard let params = d["params"] as? [String: Any],
              let u = params["update"] as? [String: Any] else { return true }
        switch u["sessionUpdate"] as? String {
        case "user_message_chunk":
            if let t = HumanText.clean(GrokSessionReader.text(u)) {
                return sink.add(.user, t, at: at)
            }
        case "agent_message_chunk":
            if let t = JSONLine.string(GrokSessionReader.text(u)) {
                return sink.add(.assistant, t, at: at)
            }
        case "agent_thought_chunk":
            if let t = JSONLine.string(GrokSessionReader.text(u)) {
                return sink.add(.thinking, t, at: at)
            }
        case "tool_call":
            return ingestToolCall(u, at: at, into: &sink)
        default:
            break
        }
        return true
    }

    private static func ingestStream(
        _ d: [String: Any],
        at: Date?,
        into sink: inout TranscriptSink
    ) -> Bool {
        switch d["type"] as? String {
        case "system":
            sink.noteGrokInit(d)
            return true
        case "result":
            sink.noteGrokResult(d)
            return true
        case "user", "assistant":
            return ingestStreamMessage(d, at: at, into: &sink)
        default:
            return true
        }
    }

    private static func ingestStreamMessage(
        _ d: [String: Any],
        at: Date?,
        into sink: inout TranscriptSink
    ) -> Bool {
        sink.sawGrokStream = true
        let type = d["type"] as? String
        guard let msg = d["message"] as? [String: Any] else { return true }
        if let s = msg["content"] as? String {
            if let notice = TaskNotice.parse(s) {
                return TranscriptClaude.addNotice(notice, at: at, into: &sink)
            }
            guard let t = HumanText.clean(s) else { return true }
            return sink.add(.user, t, at: at)
        }
        for blk in (msg["content"] as? [[String: Any]] ?? []) {
            if !ingestStreamBlock(blk, type: type, at: at, into: &sink) { return false }
        }
        return true
    }

    private static func ingestStreamBlock(
        _ blk: [String: Any],
        type: String?,
        at: Date?,
        into sink: inout TranscriptSink
    ) -> Bool {
        switch blk["type"] as? String {
        case "text":
            return ingestStreamText(blk, type: type, at: at, into: &sink)
        case "thinking":
            if let t = JSONLine.string(blk["thinking"]),
               !sink.add(.thinking, t, at: at) { return false }
        case "tool_use":
            return ingestStreamToolUse(blk, at: at, into: &sink)
        case "tool_result":
            return ingestStreamToolResult(blk, at: at, into: &sink)
        default:
            break
        }
        return true
    }

    private static func ingestStreamText(
        _ blk: [String: Any],
        type: String?,
        at: Date?,
        into sink: inout TranscriptSink
    ) -> Bool {
        guard let t = JSONLine.string(blk["text"]) else { return true }
        if type == "assistant" { return sink.add(.assistant, t, at: at) }
        if let notice = TaskNotice.parse(t) {
            return TranscriptClaude.addNotice(notice, at: at, into: &sink)
        }
        if let h = HumanText.clean(t) { return sink.add(.user, h, at: at) }
        return true
    }

    /// 요약은 `command` → `target_file` → `pattern` 순, 첫 120자.
    private static func ingestStreamToolUse(
        _ blk: [String: Any],
        at: Date?,
        into sink: inout TranscriptSink
    ) -> Bool {
        let name = blk["name"] as? String ?? "tool"
        let input = blk["input"]
        let dict = input as? [String: Any]
        let detail = ["command", "target_file", "pattern"]
            .lazy.compactMap { JSONLine.string(dict?[$0]) }.first
        let speech = AgentSpeech.utterance(toolName: name, input: input)
        let summary = detail.map { "\(name): \(TranscriptToolText.clip($0, 120))" } ?? name
        return sink.add(
            .tool, speech?.headline ?? summary,
            details: .init(
                toolName: name,
                filePaths: TranscriptToolText.filePaths(input),
                speech: speech,
                toolUseId: JSONLine.string(blk["id"]),
                editHunks: EditHunks.hunks(toolName: name, input: input, order: 0)),
            at: at)
    }

    private static func ingestStreamToolResult(
        _ blk: [String: Any],
        at: Date?,
        into sink: inout TranscriptSink
    ) -> Bool {
        let err = (blk["is_error"] as? Bool) ?? false
        let body = TranscriptToolText.flatten(blk["content"], cap: sink.options.toolTextCap)
        let text: String
        switch (err, body.isEmpty) {
        case (true, true): text = "error"
        case (true, false): text = "error ↳ " + body
        case (false, true): return true
        case (false, false): text = "↳ " + body
        }
        return sink.add(
            .toolResult, text,
            details: .init(toolUseId: JSONLine.string(blk["tool_use_id"])),
            at: at)
    }

    /// 한 줄이 blob 상한을 넘으면 큰 문자열만 잘라 읽는다. `name`·`id` 는 짧다.
    static func usableLine(_ raw: some StringProtocol) -> String {
        let n = raw.utf8.count
        if n <= JSONLine.blobStringByteCap { return String(raw) }
        let data = Data(raw.utf8)
        if n > JSONLine.perLineByteCap {
            return String(decoding: JSONLine.strippingBlobs(data), as: UTF8.self)
        }
        return String(decoding: JSONLine.clippingBlobs(data), as: UTF8.self)
    }

    static func jsonInt(_ v: Any?) -> Int? {
        if let i = v as? Int { return i }
        if let d = v as? Double { return Int(d) }
        return (v as? NSNumber).map { $0.intValue }
    }

    static func jsonDouble(_ v: Any?) -> Double? {
        if let d = v as? Double { return d }
        if let i = v as? Int { return Double(i) }
        return (v as? NSNumber).map { $0.doubleValue }
    }

    private static func ingestToolCall(
        _ u: [String: Any],
        at: Date?,
        into sink: inout TranscriptSink
    ) -> Bool {
        let name = JSONLine.string(u["title"]) ?? JSONLine.string(u["kind"]) ?? "tool"
        // 무엇을 실행했는지가 핵심이다 — 이름만으로는 이어받는 사람에게 쓸모가 없다.
        let raw = u["rawInput"] as? [String: Any]
        let detail = ["command", "file_path", "path", "pattern", "query"]
            .lazy.compactMap { JSONLine.string(raw?[$0]) }.first
        let speech = AgentSpeech.utterance(toolName: name, input: raw)
        let fallback = detail.map { "\(name): \(TranscriptToolText.clip($0, sink.options.toolTextCap))" }
        return sink.add(
            .tool, speech?.headline ?? fallback ?? name,
            details: .init(
                toolName: name,
                filePaths: TranscriptToolText.filePaths(raw),
                speech: speech,
                toolUseId: JSONLine.string(u["toolCallId"])),
            at: at)
    }
}
