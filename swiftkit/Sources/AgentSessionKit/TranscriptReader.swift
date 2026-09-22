import Foundation
import SessionKit
@_exported import AgentSessionStorageKit

/// 세션 전사본을 **발언 단위**로 읽는다.
///
/// 이 저장소 안에서만 같은 파서가 셋이었다 — `agent-deck`(전사본 뷰), `agent-session-replay`
/// (재생), `agent-worktree-control-terminal`(꼬리 미리보기). 셋 다 같은 어휘를 각자
/// 해석했고(`user_message` · `user_message_chunk` · `tool_use` · `tool_result` · `tool_call`
/// · `text` · `thinking` · `reasoning`), 따라서 **버그도 각자 갖고 있었다**
/// (2026-07-27: 이미지가 붙은 사용자 지시를 통째로 버리던 결함이 두 곳에 동시에 있었다).
///
/// 툴은 저장 구조를 자주 바꾼다. 그 지식은 한 곳에만 있어야 한다.
public enum TranscriptReader {
    /// 이미 읽어둔 텍스트에서 발언을 뽑는다(호출자가 창을 정한다 — 꼬리만 읽는 뷰가 있다).
    public static func turns(text: String, tool: AgentTool,
                             options: Options = .init()) -> (turns: [Turn], truncated: Bool) {
        let p = parsed(text: text, tool: tool, options: options)
        return (p.turns, p.truncated)
    }

    public static func parsed(text: String, tool: AgentTool,
                              options: Options = .init()) -> Parsed {
        var sink = TranscriptSink(options: options)
        for raw in text.split(separator: "\n", omittingEmptySubsequences: true) {
            if sink.truncated { break }
            // **거대한 줄을 버리지 않는다.** codex 는 이미지가 붙은 사용자 지시를 한 줄에
            // 담는다 — 버리면 그 지시까지 사라진다. blob 만 털어낸다.
            // grok 스트림은 한 줄이 181KB 까지 실측됐다. name·id 는 남기고 큰 content 만 자른다.
            let line = usableLine(raw, tool: tool)
            guard let d = JSONLine.object(line) else { continue }
            let at = JSONLine.date(d["timestamp"])
            if TranscriptAttachment.ingest(d, at: at, into: &sink) { continue }
            switch tool {
            case .claude: if !TranscriptClaude.ingest(d, at: at, into: &sink) { break }
            case .codex:  if !TranscriptCodex.ingest(d, at: at, into: &sink) { break }
            case .grok:   if !TranscriptGrok.ingest(d, at: at, into: &sink) { break }
            case .agy: break  // 전사본이 sqlite blob 이라 텍스트 줄 파서로 읽히지 않는다 — read(_:) 에서 우회.
            case .opencode, .cursor: break
            }
        }
        var out = sink.turns
        // grok ACP 는 **청크 스트림**이라 같은 화자를 이어붙인다.
        // 헤드리스 streaming-messages-json 은 줄마다 완결 발언이라 붙이지 않는다.
        if tool == .grok, !sink.sawGrokStream { out = coalesced(out) }
        return Parsed(
            turns: out,
            truncated: sink.truncated,
            grokStream: sink.sawGrokStream ? sink.grokStream : nil)
    }

    /// `offset` 이후 온전한 줄만 읽는다. `TranscriptPager.appended(since:)` 와 같은 오프셋 규약.
    public static func appended(
        path: String,
        since offset: Int,
        tool: AgentTool,
        options: Options = .init()
    ) -> Appended {
        let size = JSONLine.fileSize(path)
        guard size > offset, let fh = FileHandle(forReadingAtPath: path) else {
            return Appended(turns: [], consumedOffset: offset, truncated: false)
        }
        defer { try? fh.close() }
        try? fh.seek(toOffset: UInt64(offset))
        var data = (try? fh.read(upToCount: size - offset)) ?? Data()
        var startOffset = offset
        let prevByte: UInt8? = {
            guard offset > 0 else { return UInt8(ascii: "\n") }
            try? fh.seek(toOffset: UInt64(offset - 1))
            return ((try? fh.read(upToCount: 1)) ?? Data()).first
        }()
        if prevByte != UInt8(ascii: "\n"), let firstNL = data.firstIndex(of: UInt8(ascii: "\n")) {
            startOffset = offset + data.distance(from: data.startIndex, to: firstNL) + 1
            data = data.subdata(in: data.index(after: firstNL)..<data.endIndex)
        }
        guard let lastNL = data.lastIndex(of: UInt8(ascii: "\n")) else {
            return Appended(turns: [], consumedOffset: startOffset, truncated: false)
        }
        let consumed = startOffset + data.distance(from: data.startIndex, to: lastNL) + 1
        data = data.subdata(in: data.startIndex..<data.index(after: lastNL))
        let text = String(decoding: data, as: UTF8.self)
        let p = parsed(text: text, tool: tool, options: options)
        return Appended(
            turns: p.turns,
            consumedOffset: consumed,
            truncated: p.truncated,
            grokStream: p.grokStream)
    }

    private static func usableLine(_ raw: Substring, tool: AgentTool) -> String {
        if tool == .grok { return TranscriptGrok.usableLine(raw) }
        if raw.utf8.count > JSONLine.perLineByteCap {
            return String(decoding: JSONLine.strippingBlobs(Data(raw.utf8)), as: UTF8.self)
        }
        return String(raw)
    }

    /// 같은 화자의 연속 발언을 하나로. 툴 호출은 각각이 독립 사건이라 건드리지 않는다.
    static func coalesced(_ turns: [Turn]) -> [Turn] {
        var out: [Turn] = []
        for t in turns {
            if t.role != .tool, t.role != .toolResult, var last = out.last, last.role == t.role {
                last.text += t.text
                out[out.count - 1] = last
            } else {
                out.append(t)
            }
        }
        return out.enumerated().map { i, t in
            var t = t; t.id = i; return t
        }
    }

    /// 파일에서 바로 읽는다. grok 은 세션이 디렉터리라 `transcriptPath` 를 거친다.
    public static func read(_ ref: SessionRef, maxBytes: Int = 4 * 1024 * 1024,
                            fromTail: Bool = true,
                            options: Options = .init()) -> (turns: [Turn], truncated: Bool) {
        // Antigravity 전사본은 sqlite steps 테이블이라 줄 단위 파서를 거치지 않는다.
        if ref.tool == .agy {
            let reader = AntigravitySessionReader()
            var seenUsers: Set<String> = []
            var turnsOut: [Turn] = []
            for step in reader.steps(ref) {
                let role: Turn.Role
                let runs: [String]
                switch step.type {
                case 14: role = .user; runs = step.payloadStrings
                case 15: role = .assistant; runs = step.payloadStrings
                default: continue
                }
                guard let text = runs.first(where: { run in
                    guard AntigravitySessionReader.isHumanText(run) else { return false }
                    if role == .assistant { return true }
                    return !seenUsers.contains(run)
                }) else { continue }
                if role == .user { seenUsers.insert(text) }
                turnsOut.append(Turn(id: turnsOut.count, role: role, text: text))
            }
            return (turnsOut, false)
        }
        let path = ref.transcriptPath
        let size = JSONLine.fileSize(path)
        guard size > 0, let fh = FileHandle(forReadingAtPath: path) else { return ([], false) }
        defer { try? fh.close() }
        var clipped = false
        var data: Data
        if size > maxBytes {
            clipped = true
            if fromTail { try? fh.seek(toOffset: UInt64(size - maxBytes)) }
            data = (try? fh.read(upToCount: maxBytes)) ?? Data()
            // 임의 오프셋은 줄 중간에 떨어진다 — 첫 부분 줄은 버린다.
            if fromTail, let nl = data.firstIndex(of: UInt8(ascii: "\n")) {
                data = data.subdata(in: data.index(after: nl)..<data.endIndex)
            }
        } else {
            data = (try? fh.readToEnd()) ?? Data()
        }
        let r = turns(text: String(decoding: data, as: UTF8.self), tool: ref.tool, options: options)
        return (r.turns, r.truncated || clipped)
    }
}
