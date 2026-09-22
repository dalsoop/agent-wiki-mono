import Foundation

struct TranscriptSink {
    var turns: [TranscriptReader.Turn] = []
    var truncated = false
    var sawGrokStream = false
    var grokStream = TranscriptReader.GrokStreamMeta()
    let options: TranscriptReader.Options

    init(options: TranscriptReader.Options) {
        self.options = options
    }

    mutating func noteGrokInit(_ d: [String: Any]) {
        sawGrokStream = true
        grokStream.sessionId = JSONLine.string(d["session_id"]) ?? grokStream.sessionId
        grokStream.model = JSONLine.string(d["model"]) ?? grokStream.model
        grokStream.cwd = JSONLine.string(d["cwd"]) ?? grokStream.cwd
    }

    mutating func noteGrokResult(_ d: [String: Any]) {
        sawGrokStream = true
        grokStream.resultSubtype = JSONLine.string(d["subtype"]) ?? grokStream.resultSubtype
        grokStream.numTurns = TranscriptGrok.jsonInt(d["num_turns"]) ?? grokStream.numTurns
        grokStream.durationMs = TranscriptGrok.jsonInt(d["duration_ms"]) ?? grokStream.durationMs
        grokStream.totalCostUsd = TranscriptGrok.jsonDouble(d["total_cost_usd"]) ?? grokStream.totalCostUsd
    }

    mutating func add(
        _ role: TranscriptReader.Turn.Role,
        _ text: String,
        details: TranscriptReader.Turn.Details = .init(),
        at: Date? = nil
    ) -> Bool {
        guard turns.count < options.maxTurns else { truncated = true; return false }
        if role == .thinking, !options.includeThinking { return true }
        if role == .tool || role == .toolResult, !options.includeTools { return true }
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return true }
        var packed = details
        packed.editHunks = details.editHunks.map {
            EditHunk(path: $0.path, before: $0.before, after: $0.after, order: turns.count)
        }
        turns.append(TranscriptReader.Turn(
            id: turns.count, role: role, text: t, details: packed, at: at))
        return true
    }
}
