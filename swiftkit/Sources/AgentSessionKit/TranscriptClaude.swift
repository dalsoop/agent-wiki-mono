import Foundation

enum TranscriptClaude {
    static func ingest(
        _ d: [String: Any],
        at: Date?,
        into sink: inout TranscriptSink
    ) -> Bool {
        let type = d["type"] as? String
        guard type == "user" || type == "assistant",
              let msg = d["message"] as? [String: Any] else { return true }
        if let s = msg["content"] as? String {
            if let notice = TaskNotice.parse(s) { return addNotice(notice, at: at, into: &sink) }
            guard let t = HumanText.clean(s) else { return true }
            return sink.add(.user, t, at: at)
        }
        for blk in (msg["content"] as? [[String: Any]] ?? []) {
            if !ingestBlock(blk, type: type, at: at, into: &sink) { return false }
        }
        return true
    }

    private static func ingestBlock(
        _ blk: [String: Any],
        type: String?,
        at: Date?,
        into sink: inout TranscriptSink
    ) -> Bool {
        switch blk["type"] as? String {
        case "text":
            return ingestText(blk, type: type, at: at, into: &sink)
        case "thinking":
            if let t = JSONLine.string(blk["thinking"]),
               !sink.add(.thinking, t, at: at) { return false }
        case "tool_use":
            return ingestToolUse(blk, at: at, into: &sink)
        case "tool_result":
            let o = TranscriptToolText.flatten(blk["content"], cap: sink.options.toolTextCap)
            if !o.isEmpty, !sink.add(.toolResult, "↳ " + o, at: at) { return false }
        default:
            break
        }
        return true
    }

    private static func ingestText(
        _ blk: [String: Any],
        type: String?,
        at: Date?,
        into sink: inout TranscriptSink
    ) -> Bool {
        guard let t = JSONLine.string(blk["text"]) else { return true }
        if type == "assistant" {
            return sink.add(.assistant, t, at: at)
        }
        if let notice = TaskNotice.parse(t) {
            return addNotice(notice, at: at, into: &sink)
        }
        if let h = HumanText.clean(t) {
            return sink.add(.user, h, at: at)
        }
        return true
    }

    private static func ingestToolUse(
        _ blk: [String: Any],
        at: Date?,
        into sink: inout TranscriptSink
    ) -> Bool {
        let name = blk["name"] as? String ?? "tool"
        let speech = AgentSpeech.utterance(toolName: name, input: blk["input"])
        let text = speech?.headline ?? TranscriptToolText.summary(
            name: name, input: blk["input"], cap: sink.options.toolTextCap)
        return sink.add(
            .tool, text,
            details: .init(
                toolName: name,
                filePaths: TranscriptToolText.filePaths(blk["input"]),
                speech: speech,
                toolUseId: JSONLine.string(blk["id"]),
                editHunks: EditHunks.hunks(toolName: name, input: blk["input"], order: 0)),
            at: at)
    }

    /// 완료 알림을 결과 턴으로. 요약이 있으면 그걸, 없으면 상태를 보여준다.
    static func addNotice(
        _ notice: TaskNotice,
        at: Date?,
        into sink: inout TranscriptSink
    ) -> Bool {
        let text = notice.summary ?? "작업 \(notice.taskId) — \(notice.status)"
        return sink.add(
            .toolResult, text,
            details: .init(toolUseId: notice.toolUseId, notice: notice),
            at: at)
    }
}
