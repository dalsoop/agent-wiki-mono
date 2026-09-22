import Foundation
import SessionKit

/// Codex CLI 세션 리더.
///
/// 발견·헤드 파싱은 `SessionKit` 위임(SSOT). 이 타입은 팩 증류에 필요한 것만 새로 한다.
///
/// 봉투가 두 겹이라 주의: 세션 메타는 **최상위** `{"type":"session_meta","payload":{…}}` 이고,
/// 대화 내용은 `payload.type` 또는 `response_item.payload.type` 아래 있다.
/// `SessionLine.codexPayload` 가 그 두 모양을 흡수한다.
public struct CodexSessionReader: Sendable {
    let minSize: Int

    public init(minSize: Int = 2_048) {
        self.minSize = minSize
    }

    // MARK: - 발견

    public func discover(limit: Int = 500, since: Date? = nil) -> [SessionRef] {
        // thread_name 은 별도 인덱스 파일에 있다 — 세션마다 열지 않고 한 번만 읽는다.
        let names: [String: String] = SessionRoots.codexSessionIndex
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) }
            .map { SessionMeta.codexIndex(text: $0) } ?? [:]

        return SessionRoots.enumerateJSONL(runtimes: [.codex], minSize: minSize, since: since)
            .lazy
            .prefix(limit)
            .compactMap { ref($0, names: names) }
            .sorted { $0.lastActive > $1.lastActive }
    }

    public func discover(limit: Int) -> [SessionRef] {
        discover(limit: limit, since: nil)
    }

    /// 세션 id 한 건 조회. 인덱스·파일명 UUID 를 본다.
    public func find(id: String) -> SessionRef? {
        findPrefix(id: id, limit: 1).first
    }

    /// 접두사로 최대 `limit` 개까지 매치를 반환한다. 정확 일치가 있으면 그것만 반환한다.
    public func findPrefix(id: String, limit: Int) -> [SessionRef] {
        let needle = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard needle.count >= 8 else { return [] }
        let names: [String: String] = SessionRoots.codexSessionIndex
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) }
            .map { SessionMeta.codexIndex(text: $0) } ?? [:]
        var hits: [SessionRef] = []
        for f in SessionRoots.enumerateJSONL(runtimes: [.codex], minSize: minSize) {
            guard let r = ref(f, names: names) else { continue }
            if r.id == needle { return [r] }
            if r.id.hasPrefix(needle) {
                hits.append(r)
                if hits.count >= limit { break }
            }
        }
        return hits
    }

    private func ref(_ f: SessionRoots.File, names: [String: String]) -> SessionRef? {
        let head = SessionHead.read(f.url)
        let meta = SessionMeta.codex(head: head)
        let id = meta.id
            ?? SessionIdent.codexUUID(fromFileName: f.url.lastPathComponent)
            ?? f.url.deletingPathExtension().lastPathComponent
        // 제목: thread_name > 닉네임 > 첫 사람 프롬프트.
        let title = names[id] ?? meta.nickname ?? Self.firstPrompt(head: head)
        return SessionRef(
            tool: .codex,
            id: id,
            cwd: meta.cwd ?? "",
            title: title.map { HumanText.oneLine($0, cap: 120) },
            lastActive: f.modifiedAt,
            path: f.url.path,
            messageCount: max(1, f.sizeBytes / 2_000)
        )
    }

    static func firstPrompt(head: String) -> String? {
        for line in SessionHead.lines(head) {
            guard let d = SessionLine.decode(line),
                  let p = SessionLine.codexPayload(d),
                  p["type"] as? String == "user_message",
                  let t = HumanText.clean(p["message"] as? String)
            else { continue }
            return t
        }
        return nil
    }

    // MARK: - 파싱

    /// 로컬 코덱스 세션 전수 조사(codex-cli 0.145.0)로 확정한 어휘.
    ///
    /// 초판은 `function_call` 만 봤다가 팩 근거 부족률이 75% 였다 — 요즘 codex 는
    /// 셸 실행을 `exec_command_end` 로, 파일 편집을 `patch_apply_end` /
    /// `custom_tool_call(apply_patch)` 로 남긴다. `doctor` 가 이 누락을 잡아냈다.
    static let knownPayloadTypes: Set<String> = [
        "session_meta", "user_message", "agent_message", "message",
        "function_call", "function_call_output",
        "exec_command_begin", "exec_command_end",
        "custom_tool_call", "custom_tool_call_output",
        "patch_apply_begin", "patch_apply_end",
        "reasoning", "agent_reasoning", "event_msg", "turn_context",
        "compacted", "context_compacted", "token_count", "response_item",
        "task_started", "task_complete", "turn_aborted",
        "web_search_call", "web_search_end", "mcp_tool_call_end",
        "thread_name_updated", "view_image_tool_call", "error",
        // 2026-07-29 doctor 실측(codex-cli 0.145): 이미지 생성 도구. 팩 증류에 안 쓰지만
        // 모르는 이벤트로 세면 health 가 깨져 함대 본업 점수가 0 이 된다.
        "image_generation_call", "image_generation_end",
    ]

    public func digest(_ ref: SessionRef, window: DigestWindow = .standard) -> SessionDigest {
        var d = SessionDigest(ref: ref)
        var lastPlan: [PlanEntry] = []
        let readPlan = window.plan(fileSize: JSONLine.fileSize(ref.path))
        d.truncated = readPlan.isTruncated

        if case let .headAndTail(headBytes, _) = readPlan {
            JSONLine.forEachLine(path: ref.path, maxBytes: headBytes) { line in
                guard let p = SessionLine.codexPayload(line),
                      p["type"] as? String == "user_message",
                      let t = HumanText.clean(p["message"] as? String)
                else { return true }
                d.userMessages.append(t); d.turns.append(.init(.user, t))
                return false
            }
        }

        let offset: Int
        if case let .headAndTail(_, tailOffset) = readPlan { offset = tailOffset } else { offset = 0 }
        JSONLine.forEachLine(path: ref.path, from: offset) { line in
            guard let p = SessionLine.codexPayload(line), let type = p["type"] as? String else { return true }
            if !Self.knownPayloadTypes.contains(type) {
                d.unknownEvents[type, default: 0] += 1
                return true
            }
            switch type {
            case "user_message":
                if let t = HumanText.clean(p["message"] as? String) { d.userMessages.append(t); d.turns.append(.init(.user, t)) }
            case "agent_message":
                if let t = JSONLine.string(p["message"]) { d.agentMessages.append(t); d.turns.append(.init(.agent, t)) }
            case "function_call":
                Self.absorbCall(p, into: &d, lastPlan: &lastPlan)
            case "exec_command_end":
                // 셸 실행의 정본. command 는 argv 배열(`["/bin/zsh","-lc","…"]`).
                if let argv = p["command"] as? [String], !argv.isEmpty {
                    d.commands.append(Self.readableCommand(argv))
                }
            case "patch_apply_end":
                // changes 의 키가 편집된 파일 절대경로다 — 가장 정확한 파일 출처.
                for path in (p["changes"] as? [String: Any])?.keys ?? [:].keys {
                    d.files[path, default: 0] += 1
                }
            case "custom_tool_call":
                // apply_patch 는 patch_apply_end 가 못 남은 경우의 폴백.
                if p["name"] as? String == "apply_patch", let input = p["input"] as? String {
                    for path in Self.patchedFiles(input) { d.files[path, default: 0] += 1 }
                }
            default:
                break
            }
            return true
        }

        d.plan = lastPlan
        return d
    }

    /// `["/bin/zsh","-lc","swift test"]` → `swift test`.
    /// 셸 래퍼는 매 줄 반복돼 팩을 덮으므로 벗겨낸다.
    public static func readableCommand(_ argv: [String]) -> String {
        if argv.count >= 3, argv[1] == "-lc" || argv[1] == "-c" {
            return argv[2]
        }
        return argv.joined(separator: " ")
    }

    /// apply_patch 본문에서 파일 경로를 뽑는다.
    /// 형식: `*** Add File: <경로>` / `*** Update File: <경로>` / `*** Delete File: <경로>`.
    package static func patchedFiles(_ patch: String) -> [String] {
        patch.split(separator: "\n").compactMap { line in
            guard line.hasPrefix("*** ") else { return nil }
            for verb in ["Add File: ", "Update File: ", "Delete File: "] where line.contains(verb) {
                guard let r = line.range(of: verb) else { continue }
                let path = line[r.upperBound...].trimmingCharacters(in: .whitespaces)
                return path.isEmpty ? nil : path
            }
            return nil
        }
    }

    private static func absorbCall(
        _ p: [String: Any], into d: inout SessionDigest, lastPlan: inout [PlanEntry]
    ) {
        let name = p["name"] as? String ?? ""
        // arguments 는 JSON **문자열**이라 한 번 더 파싱해야 한다.
        guard let argStr = p["arguments"] as? String, let args = JSONLine.object(argStr) else { return }

        if name == "update_plan", let steps = args["plan"] as? [[String: Any]] {
            lastPlan = steps.compactMap { s in
                guard let c = JSONLine.string(s["step"]) ?? JSONLine.string(s["content"]) else { return nil }
                return PlanEntry(content: c, status: PlanEntry.status(from: s["status"] as? String))
            }
            return
        }
        for key in ["file_path", "path"] {
            if let f = JSONLine.string(args[key]) { d.files[f, default: 0] += 1 }
        }
        // shell 호출은 command 가 argv 배열로 온다.
        if let arr = args["command"] as? [String], !arr.isEmpty {
            d.commands.append(arr.joined(separator: " "))
        } else if let c = JSONLine.string(args["command"]) {
            d.commands.append(c)
        }
    }
}
