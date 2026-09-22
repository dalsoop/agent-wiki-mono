import Foundation
import SessionKit

/// Grok Build 세션 리더.
///
/// 저장 구조 (실측: grok 0.2.112, 로컬 66 세션 전수 확인):
/// ```
/// ~/.grok/sessions/<percent-encoded-cwd>/
///   prompt_history.jsonl            ← 그룹 단위, 세션 아님(무시)
///   <session-uuid>/
///     summary.json                  ← 메타: id, cwd, 제목, 시각, 모델, 메시지 수, git remote
///     updates.jsonl                 ← **정본 대화 로그** (ACP session/update 스트림)
///     chat_history.jsonl            ← 모델에 보낸 원본(중복이라 안 씀)
///     events.jsonl, plan.json, …    ← 무시
/// ```
///
/// `updates.jsonl` 은 **ACP(Agent Client Protocol)** 스트림이라 공개 표준이다. 한 줄 봉투:
/// `{"method": "session/update", "params": {"update": {"sessionUpdate": "<종류>", …}}, "timestamp": …}`
///
/// 핸드오프에 결정적인 건 grok 이 스스로 남기는 세 가지다 — 다른 툴엔 없다:
/// - `session_recap.summary`  : 에이전트 자체 서사 요약
/// - `goal_updated.objective` : 선언된 목표
/// - `plan.entries[].status`  : 상태 붙은 계획
public struct GrokSessionReader: Sendable {
    public let root: String

    public init(root: String = SessionRoots.grokSessions.path) {
        self.root = root
    }

    // MARK: - 발견

    public func discover(limit: Int = 500, since: Date? = nil) -> [SessionRef] {
        // 세션마다 summary.json 을 여는 건 **잘라낸 뒤**에 한다. 4,000 세션을 전부 읽고 나서
        // prefix(limit) 하던 옛 방식은 limit 과 무관하게 비용이 세션 수에 비례했다.
        // 그룹 순서는 cwd 인코딩이라 최근이 앞에 오지 않으므로, 싼 stat(mtime)으로 먼저 정렬한다.
        let candidates = SessionRoots.scanGrok(root: URL(fileURLWithPath: root, isDirectory: true),
                                               minSize: 0, since: since)
            .sorted { $0.modifiedAt > $1.modifiedAt }
            .prefix(limit)
        return candidates.map { file in
            let dir = file.url.deletingLastPathComponent()
            let groupCwd = dir.deletingLastPathComponent().lastPathComponent
            return ref(sessionDir: dir.path, id: dir.lastPathComponent,
                       fallbackCwd: groupCwd.removingPercentEncoding ?? groupCwd)
        }
        .sorted { $0.lastActive > $1.lastActive }
    }

    public func discover(limit: Int) -> [SessionRef] {
        discover(limit: limit, since: nil)
    }

    /// 세션 id 한 건 조회.
    public func find(id: String) -> SessionRef? {
        findPrefix(id: id, limit: 1).first
    }

    /// 접두사로 최대 `limit` 개까지 매치를 반환한다. 정확 일치가 있으면 그것만 반환한다.
    public func findPrefix(id: String, limit: Int) -> [SessionRef] {
        let needle = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard needle.count >= 8 else { return [] }
        let fm = FileManager.default
        guard let groups = SessionRoots.contents(ofDirectoryPath: root) else { return [] }
        var hits: [SessionRef] = []
        for group in groups {
            let groupPath = root + "/" + group
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: groupPath, isDirectory: &isDir), isDir.boolValue else { continue }
            let groupCwd = group.removingPercentEncoding ?? group
            guard let sessions = SessionRoots.contents(ofDirectoryPath: groupPath) else { continue }
            for sid in sessions {
                guard sid == needle || sid.hasPrefix(needle) else { continue }
                let dir = groupPath + "/" + sid
                guard fm.fileExists(atPath: dir + "/updates.jsonl") else { continue }
                let r = ref(sessionDir: dir, id: sid, fallbackCwd: groupCwd)
                if sid == needle { return [r] }
                hits.append(r)
                if hits.count >= limit { return hits }
            }
        }
        return hits
    }

    private func ref(sessionDir: String, id: String, fallbackCwd: String) -> SessionRef {
        var title: String?
        var cwd = fallbackCwd
        var updated = Date.distantPast
        var count = 0
        // 로그가 아직 없으면 distantPast — 정렬에서 뒤로 밀린다.
        let fileMtime = SessionRoots.modificationDate(atPath: sessionDir + "/updates.jsonl") ?? .distantPast
        if let o = Self.summary(at: sessionDir + "/summary.json") {
            title = JSONLine.string(o["session_summary"])
            if let info = o["info"] as? [String: Any], let c = JSONLine.string(info["cwd"]) { cwd = c }
            updated = JSONLine.date(o["updated_at"]) ?? updated
            count = (o["num_chat_messages"] as? Int) ?? 0
        }
        // summary.updated_at 이 안 바뀌는 세션이 있다. 로그 mtime 이 더 최근이면 그걸 쓴다.
        if fileMtime > updated { updated = fileMtime }
        return SessionRef(tool: .grok, id: id, cwd: cwd, title: title,
                          lastActive: updated, path: sessionDir, messageCount: count)
    }

    /// summary.json 을 읽는다. 손상됐거나 없으면 nil — 세션 목록은 로그 mtime 만으로도 선다.
    private static func summary(at path: String) -> [String: Any]? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        do {
            return try JSONSerialization.jsonObject(with: data) as? [String: Any]
        } catch {
            // grok 이 쓰다 만 summary.json 은 실측으로 존재한다. 제목만 잃고 세션은 남긴다.
            return nil
        }
    }

    // MARK: - 파싱

    /// 파서가 아는 이벤트 종류. 여기 없는 게 나오면 `unknownEvents` 로 세어 드리프트 감지에 쓴다.
    ///
    /// 의도적으로 무시하는 것도 "안다"로 친다 — 모르는 것과 구분해야 경보가 의미를 갖는다.
    static let knownEvents: Set<String> = [
        "user_message_chunk", "agent_message_chunk", "agent_thought_chunk",
        "tool_call", "tool_call_update", "plan", "session_recap", "goal_updated",
        "turn_completed", "task_completed", "task_backgrounded",
        "hook_execution", "subagent_spawned", "subagent_finished",
        "auto_compact_started", "auto_compact_completed", "compaction_checkpoint",
        "retry_state", "available_commands_update", "current_mode_update",
    ]

    public func digest(_ ref: SessionRef, window: DigestWindow = .standard) -> SessionDigest {
        var d = SessionDigest(ref: ref)
        var plans: [[PlanEntry]] = []
        let file = ref.transcriptPath
        let readPlan = window.plan(fileSize: JSONLine.fileSize(file))
        d.truncated = readPlan.isTruncated

        // 원래 목표(첫 사용자 발언)는 머리에만 있다.
        if case let .headAndTail(headBytes, _) = readPlan {
            Self.absorbOriginalGoal(file: file, headBytes: headBytes, into: &d)
        }

        let offset: Int
        if case let .headAndTail(_, tailOffset) = readPlan { offset = tailOffset } else { offset = 0 }
        JSONLine.forEachLine(path: file, from: offset) { line in
            guard let params = line["params"] as? [String: Any],
                  let u = params["update"] as? [String: Any],
                  let kind = u["sessionUpdate"] as? String
            else { return true }

            if !Self.knownEvents.contains(kind) {
                d.unknownEvents[kind, default: 0] += 1
                return true
            }
            Self.absorbEvent(kind: kind, u, into: &d, plans: &plans)
            return true
        }

        d.plan = plans.last ?? []
        return d
    }

    private static func absorbOriginalGoal(file: String, headBytes: Int, into d: inout SessionDigest) {
        JSONLine.forEachLine(path: file, maxBytes: headBytes) { line in
            guard let params = line["params"] as? [String: Any],
                  let u = params["update"] as? [String: Any],
                  u["sessionUpdate"] as? String == "user_message_chunk",
                  let t = HumanText.clean(Self.text(u))
            else { return true }
            d.userMessages.append(t); d.turns.append(.init(.user, t))
            return false
        }
    }

    /// 알려진 이벤트 한 건을 digest 에 흡수한다. `digest` 본체의 분기를 여기로 뽑았다.
    private static func absorbEvent(kind: String, _ u: [String: Any],
                                    into d: inout SessionDigest, plans: inout [[PlanEntry]]) {
        switch kind {
        case "user_message_chunk":
            // grok 의 청크는 스트리밍 토큰이 아니라 **완결 메시지**다(실측).
            if let t = HumanText.clean(Self.text(u)) { d.userMessages.append(t); d.turns.append(.init(.user, t)) }
        case "agent_message_chunk":
            if let t = JSONLine.string(Self.text(u)) { d.agentMessages.append(t); d.turns.append(.init(.agent, t)) }
        case "session_recap":
            if let s = JSONLine.string(u["summary"]) { d.recaps.append(s) }
        case "goal_updated":
            if let g = JSONLine.string(u["objective"]) { d.goals.append(g) }
        case "plan":
            let entries = Self.planEntries(u)
            if !entries.isEmpty { plans.append(entries) }
        case "turn_completed":
            d.stopReason = JSONLine.string(u["stop_reason"]) ?? d.stopReason
        case "task_completed":
            if let snap = u["task_snapshot"] as? [String: Any],
               let c = JSONLine.string(snap["command"]) { d.commands.append(c) }
        case "tool_call":
            Self.absorbToolCall(u, into: &d)
        case "tool_call_update":
            Self.absorbToolResult(u, into: &d)
        default:
            break  // thought/hook/compact 등은 팩에 넣지 않는다.
        }
    }

    private static func planEntries(_ u: [String: Any]) -> [PlanEntry] {
        (u["entries"] as? [[String: Any]] ?? []).compactMap { e -> PlanEntry? in
            guard let c = JSONLine.string(e["content"]) else { return nil }
            return PlanEntry(content: c, status: PlanEntry.status(from: e["status"] as? String))
        }
    }

    public static func text(_ u: [String: Any]) -> String? {
        (u["content"] as? [String: Any])?["text"] as? String
    }

    private static func absorbToolCall(_ u: [String: Any], into d: inout SessionDigest) {
        for loc in (u["locations"] as? [[String: Any]] ?? []) {
            if let p = JSONLine.string(loc["path"]) { d.files[p, default: 0] += 1 }
        }
        guard let raw = u["rawInput"] as? [String: Any] else { return }
        for key in ["file_path", "path", "filePath"] {
            if let p = JSONLine.string(raw[key]) { d.files[p, default: 0] += 1 }
        }
        if let c = JSONLine.string(raw["command"]) { d.commands.append(c) }
    }

    /// 완료된 호출에서 명령 + stdout 첫 줄을 건진다.
    /// `tool_call` 의 rawInput.command 만 보면 출력(호스트 문자열)이 원장에 안 남는다.
    package static func absorbToolResult(_ u: [String: Any], into d: inout SessionDigest) {
        let rawOut = u["rawOutput"] as? [String: Any]
        let cmd = JSONLine.string(rawOut?["command"])
            ?? JSONLine.string((u["rawInput"] as? [String: Any])?["command"])
        guard let cmd, !cmd.isEmpty else { return }
        var text: String?
        if let arr = u["content"] as? [[String: Any]] {
            for item in arr {
                if let inner = item["content"] as? [String: Any],
                   let t = JSONLine.string(inner["text"]), !t.isEmpty {
                    text = t
                    break
                }
            }
        }
        if text == nil { text = JSONLine.string(rawOut?["output_for_prompt"]) }
        if d.commands.last != cmd { d.commands.append(cmd) }
        d.commandOutputs.append(CommandOutput(command: cmd, stdoutLine: firstLine(text)))
        if d.commandOutputs.count > 80 {
            d.commandOutputs.removeFirst(d.commandOutputs.count - 80)
        }
    }

    static func firstLine(_ raw: String?, cap: Int = 160) -> String? {
        guard let raw else { return nil }
        let line = raw.split(whereSeparator: \.isNewline).first.map(String.init) ?? raw
        let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        return t.count <= cap ? t : String(t.prefix(cap - 1)) + "…"
    }
}
