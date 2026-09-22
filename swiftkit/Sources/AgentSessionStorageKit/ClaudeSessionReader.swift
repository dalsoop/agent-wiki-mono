import FastDiskIOKit
import Foundation
import SessionKit

/// Claude Code 세션 리더.
///
/// **발견·헤드 파싱은 swiftkit `SessionKit` 에 위임한다** — 그게 이 모노레포의 SSOT 다
/// (agent-deck·agent-session-replay·agent-fleet-map·mcp-manager 에서 중복되던 걸 추출한 것).
/// 이 타입이 새로 하는 일은 **팩 증류에 필요한 것**뿐이다: 계획 상태(TodoWrite), 건드린 파일,
/// 실행 명령.
///
/// 한 줄 봉투: `{"type":"user"|"assistant","message":{"content": String | [블록]},"cwd":…}`
/// 블록: `text` · `thinking` · `tool_use` · `tool_result`.
///
/// grok 과 달리 **자체 서사 요약(recap)이 없다.** 계획도 `TodoWrite` 를 쓴 세션에만 있다
/// (실측 18/60). 그래서 claude 출신 팩은 규칙 기반만으로는 상대적으로 얇다.
public struct ClaudeSessionReader: Sendable {
    /// 빈 껍데기 세션(사람 프롬프트 없이 만들어졌다 버려진 것)을 걸러내는 하한.
    let minSize: Int

    public init(minSize: Int = 2_048) {
        self.minSize = minSize
    }

    // MARK: - 발견

    public func discover(limit: Int = 500, since: Date? = nil) -> [SessionRef] {
        SessionRoots.enumerateJSONL(runtimes: [.claude], minSize: minSize, since: since)
            .lazy
            .prefix(limit)
            .compactMap { ref($0) }
            .sorted { $0.lastActive > $1.lastActive }
    }

    public func discover(limit: Int) -> [SessionRef] {
        discover(limit: limit, since: nil)
    }

    /// 세션 id(전체 UUID 또는 8자 이상 prefix)로 한 건만 찾는다.
    /// 전수 정렬 없이 projects 트리를 돌다 **첫 정확 일치**에서 바로 반환 — session 카드 CLI 용.
    public func find(id: String) -> SessionRef? {
        findPrefix(id: id, limit: 1).first
    }

    /// 접두사로 최대 `limit` 개까지 매치를 반환한다. 정확 일치가 있으면 그것만 반환한다.
    public func findPrefix(id: String, limit: Int) -> [SessionRef] {
        let needle = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard needle.count >= 8 else { return [] }
        let root = SessionRoots.claudeProjects
        let entries = FastDirectoryScanner.scanEntries(in: root.path)
        var hits: [SessionRef] = []
        for entry in entries {
            guard !entry.isDirectory else { continue }
            guard !entry.name.hasPrefix(".") else { continue }
            guard entry.name.hasSuffix(".jsonl") else { continue }
            let url = URL(fileURLWithPath: entry.path)
            if url.deletingLastPathComponent().lastPathComponent == "subagents" { continue }
            let base = String(entry.name.dropLast(".jsonl".count))
            guard base == needle || base.hasPrefix(needle) else { continue }
            let size = Int(entry.size)
            if size < minSize { continue }
            let file = SessionRoots.File(
                url: url, runtime: .claude,
                modifiedAt: entry.modifiedAt,
                sizeBytes: size
            )
            if base == needle, let r = ref(file) { return [r] }
            if let r = ref(file) {
                hits.append(r)
                if hits.count >= limit { break }
            }
        }
        return hits
    }

    private func ref(_ f: SessionRoots.File) -> SessionRef? {
        let meta = SessionMeta.claude(head: SessionHead.read(f.url), clean: HumanText.cleanContent)
        // 사람 프롬프트가 없으면 `claude --resume` 목록에도 안 뜨는 세션이다.
        guard let prompt = meta.firstPrompt else { return nil }
        return SessionRef(
            tool: .claude,
            id: f.url.deletingPathExtension().lastPathComponent,
            cwd: meta.cwd ?? "",
            title: HumanText.oneLine(prompt, cap: 120),
            lastActive: f.modifiedAt,
            path: f.url.path,
            messageCount: max(1, f.sizeBytes / 2_000)  // 대략치 — 정렬·굵기 판단용
        )
    }

    // MARK: - 파싱

    /// 로컬 세션 60개 전수 조사로 확정한 줄 종류.
    /// 내용을 안 쓰는 메타데이터 줄까지 **명시적으로** 넣는다 — "모르는 것"만 남아야
    /// `doctor` 의 드리프트 경보가 신호로 쓸모가 있다.
    static let knownLineTypes: Set<String> = [
        "user", "assistant", "system", "summary", "progress",
        "file-history-snapshot", "file-history-delta",
        "last-prompt", "ai-title", "mode", "permission-mode",
        "attachment", "queue-operation", "agent-name", "pr-link", "frame-link",
        // 2026-07-29 doctor 실측: worktree/세션 이전 메타. 팩에 안 쓰지만 "안다"로 쳐야
        // 드리프트 경보가 신호로 남는다(339× 오탐이 함대 health 를 ok:false 로 만들었다).
        "relocated", "worktree-state",
    ]

    /// - Parameter window: 읽을 구간. 기본은 머리+꼬리만 읽어 큰 세션에서 빠르다.
    ///   `.full` 은 드리프트 감지(`doctor`)처럼 빠짐없이 봐야 할 때.
    public func digest(_ ref: SessionRef, window: DigestWindow = .standard) -> SessionDigest {
        var d = SessionDigest(ref: ref)
        var lastTodos: [PlanEntry] = []
        let plan = window.plan(fileSize: JSONLine.fileSize(ref.path))
        d.truncated = plan.isTruncated

        // 원래 목표(첫 사용자 지시)만 머리에서 건진다 — 꼬리에는 없다.
        if case let .headAndTail(headBytes, _) = plan {
            JSONLine.forEachLine(path: ref.path, maxBytes: headBytes) { line in
                guard line["type"] as? String == "user",
                      let msg = line["message"] as? [String: Any],
                      let first = HumanText.cleanContent(msg["content"])
                else { return true }
                d.userMessages.append(first); d.turns.append(.init(.user, first))
                return false   // 첫 하나면 충분하다
            }
        }

        let offset: Int
        if case let .headAndTail(_, tailOffset) = plan { offset = tailOffset } else { offset = 0 }
        JSONLine.forEachLine(path: ref.path, from: offset) { line in
            let type = line["type"] as? String
            guard type == "user" || type == "assistant",
                  let msg = line["message"] as? [String: Any]
            else {
                if let t = type, !Self.knownLineTypes.contains(t) { d.unknownEvents[t, default: 0] += 1 }
                return true
            }
            let content = msg["content"]
            if let s = content as? String {
                if type == "user", let t = HumanText.clean(s) { d.userMessages.append(t); d.turns.append(.init(.user, t)) }
                return true
            }
            for blk in (content as? [[String: Any]] ?? []) {
                switch blk["type"] as? String {
                case "text":
                    guard let t = JSONLine.string(blk["text"]) else { break }
                    if type == "assistant" { d.agentMessages.append(t); d.turns.append(.init(.agent, t)) }
                    else if let h = HumanText.clean(t) { d.userMessages.append(h); d.turns.append(.init(.user, h)) }
                case "tool_use":
                    Self.absorbToolUse(blk, into: &d, lastTodos: &lastTodos)
                default:
                    break  // thinking / tool_result 는 팩에 넣지 않는다.
                }
            }
            return true
        }

        d.plan = lastTodos
        return d
    }

    private static func absorbToolUse(
        _ blk: [String: Any], into d: inout SessionDigest, lastTodos: inout [PlanEntry]
    ) {
        let name = blk["name"] as? String ?? ""
        guard let input = blk["input"] as? [String: Any] else { return }

        // 계획 상태는 TodoWrite 에서만 나온다. 마지막 것이 최종 상태다.
        if name == "TodoWrite", let todos = input["todos"] as? [[String: Any]] {
            lastTodos = todos.compactMap { t in
                guard let c = JSONLine.string(t["content"]) else { return nil }
                return PlanEntry(content: c, status: PlanEntry.status(from: t["status"] as? String))
            }
            return
        }
        for key in ["file_path", "path", "notebook_path"] {
            if let p = JSONLine.string(input[key]) { d.files[p, default: 0] += 1 }
        }
        if name == "Bash", let c = JSONLine.string(input["command"]) { d.commands.append(c) }
    }
}
