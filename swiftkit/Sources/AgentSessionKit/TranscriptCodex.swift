import Foundation
import SessionKit

enum TranscriptCodex {
    static func ingest(
        _ d: [String: Any],
        at: Date?,
        into sink: inout TranscriptSink
    ) -> Bool {
        guard let p = SessionLine.codexPayload(d) else { return true }
        switch p["type"] as? String {
        case "user_message":
            if let t = HumanText.clean(p["message"] as? String) {
                return sink.add(.user, t, at: at)
            }
        case "agent_message":
            if let t = JSONLine.string(p["message"]) {
                return sink.add(.assistant, t, at: at)
            }
        case "agent_reasoning", "reasoning":
            if let t = reasoningText(p) { return sink.add(.thinking, t, at: at) }
        case "exec_command_end":
            return ingestExec(p, at: at, into: &sink)
        case "function_call", "custom_tool_call":
            return ingestFunctionCall(p, at: at, into: &sink)
        case "function_call_output", "custom_tool_call_output":
            // 결과가 없으면 무엇을 했는지만 알고 어떻게 됐는지는 모른다.
            let o = TranscriptToolText.flatten(p["output"] ?? p["result"], cap: sink.options.toolTextCap)
            if !o.isEmpty { return sink.add(.toolResult, "↳ " + o, at: at) }
        case "message":
            return ingestMessage(p, at: at, into: &sink)
        default:
            break
        }
        return true
    }

    private static func reasoningText(_ p: [String: Any]) -> String? {
        // `summary` 는 문자열일 수도, `[{type:summary_text, text:…}]` 블록일 수도 있다.
        if let t = JSONLine.string(p["text"]) ?? JSONLine.string(p["summary"]) { return t }
        let blocks = (p["summary"] as? [[String: Any]] ?? [])
            .compactMap { JSONLine.string($0["text"]) }
        return blocks.isEmpty ? nil : blocks.joined(separator: " ")
    }

    private static func ingestExec(
        _ p: [String: Any],
        at: Date?,
        into sink: inout TranscriptSink
    ) -> Bool {
        guard let argv = p["command"] as? [String], !argv.isEmpty else { return true }
        // shell 로 넘긴 apply_patch 도 편집이다 — 헤더에서 대상 파일을 건진다.
        return sink.add(
            .tool, CodexSessionReader.readableCommand(argv),
            details: .init(
                toolName: "shell",
                filePaths: TranscriptToolText.patchTargets(argv.joined(separator: "\n"))),
            at: at)
    }

    private static func ingestFunctionCall(
        _ p: [String: Any],
        at: Date?,
        into sink: inout TranscriptSink
    ) -> Bool {
        let name = p["name"] as? String ?? "tool"
        let input = p["arguments"] ?? p["input"]
        let speech = AgentSpeech.utterance(toolName: name, input: input)
        return sink.add(
            .tool,
            speech?.headline ?? TranscriptToolText.summary(
                name: name, input: input, cap: sink.options.toolTextCap),
            details: .init(
                toolName: name,
                filePaths: TranscriptToolText.filePaths(input),
                speech: speech,
                toolUseId: JSONLine.string(p["call_id"] ?? p["id"])),
            at: at)
    }

    private static func ingestMessage(
        _ p: [String: Any],
        at: Date?,
        into sink: inout TranscriptSink
    ) -> Bool {
        // response_item 봉투: role + content 블록.
        let role = p["role"] as? String
        for blk in (p["content"] as? [[String: Any]] ?? []) {
            guard let t = JSONLine.string(blk["text"]) else { continue }
            if role == "user" {
                if let h = HumanText.clean(t), !sink.add(.user, h, at: at) { return false }
            } else if !sink.add(.assistant, t, at: at) {
                return false
            }
        }
        return true
    }
}
