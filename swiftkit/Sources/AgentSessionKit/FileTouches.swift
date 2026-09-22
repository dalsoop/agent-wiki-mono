import Foundation

/// 한 세션에서 에이전트가 **건드린 파일**과 그 성격(읽음/고침).
///
/// 두 앱이 같은 질문에 반쪽씩 답하고 있었다 — `agent-worktree-control-terminal` 의
/// `SessionEdits` 는 **쓰기만**(그래서 md 를 스무 개 읽어도 "편집한 파일 없음"),
/// `agent-session-replay` 의 `FileAttention` 은 읽기·쓰기를 세지만 그 앱 안에만 있었다.
/// 세션 텍스트에서 경로를 다시 정규식으로 긁는 대신 `TranscriptReader.Turn.filePaths`
/// 위에 얹는다 — 툴 저장 구조의 지식은 리더 한 곳에만 둔다.
public struct FileTouch: Sendable, Equatable, Identifiable {
    public let path: String
    /// 읽기 호출 수(Read/Grep/Glob/NotebookRead…).
    public var reads: Int
    /// 쓰기 호출 수(Edit/Write/MultiEdit/apply_patch…).
    public var writes: Int
    /// 이 파일이 마지막으로 등장한 발언 순번 — 최근 순 정렬의 기준.
    public var lastTurn: Int

    public var id: String { path }
    public var total: Int { reads + writes }
    public var isEdited: Bool { writes > 0 }

    public init(path: String, reads: Int = 0, writes: Int = 0, lastTurn: Int = 0) {
        self.path = path
        self.reads = reads
        self.writes = writes
        self.lastTurn = lastTurn
    }
}

public enum FileTouches {
    /// 쓰기로 보는 툴 이름(소문자 비교).
    static let writeTools: Set<String> = [
        "edit", "write", "multiedit", "notebookedit", "apply_patch", "applypatch", "str_replace_editor",
    ]
    /// 읽기로 보는 툴 이름.
    static let readTools: Set<String> = [
        "read", "grep", "glob", "notebookread", "view", "search",
    ]

    /// 툴 이름이 쓰기인지 — 앱마다 다시 나열하지 않게 여기서 판정한다.
    public static func isWrite(toolName: String?) -> Bool {
        writeTools.contains((toolName ?? "").lowercased())
    }

    /// 툴 이름이 읽기인지.
    public static func isRead(toolName: String?) -> Bool {
        readTools.contains((toolName ?? "").lowercased())
    }

    /// 발언 목록에서 파일 접촉을 집계한다. 순수 — 테스트 대상.
    ///
    /// 툴 이름을 모르는 경우(codex `shell` 로 넘어온 apply_patch 등)는 **경로가 patch
    /// 헤더에서 나왔다는 사실 자체**가 쓰기 근거라, 이름 대신 그것으로 판정한다.
    public static func collect(_ turns: [TranscriptReader.Turn]) -> [FileTouch] {
        var entries: [(path: String, isWrite: Bool, order: Int)] = []
        for turn in turns where turn.role == .tool {
            guard !turn.filePaths.isEmpty else { continue }
            let name = (turn.toolName ?? "").lowercased()
            let patch = turn.text.contains("apply_patch") || turn.text.contains("*** ")
            let write = isWrite(toolName: name) || (!readTools.contains(name) && patch)
            entries += turn.filePaths.map { ($0, write, turn.id) }
        }
        return tally(entries)
    }

    /// (경로, 쓰기여부, 순번) 목록을 파일별로 합산한다 — 파서가 다른 앱들의 공통 바닥.
    /// `agent-session-replay` 는 diff 까지 캡처하는 자체 파서를 쓰므로 발언 대신 여기로 들어온다.
    /// 반환은 **최근 접촉 우선**. 히트맵처럼 다른 순서가 필요하면 호출부가 다시 정렬한다.
    public static func tally(_ entries: [(path: String, isWrite: Bool, order: Int)]) -> [FileTouch] {
        var map: [String: FileTouch] = [:]
        for e in entries {
            var t = map[e.path] ?? FileTouch(path: e.path)
            if e.isWrite { t.writes += 1 } else { t.reads += 1 }
            t.lastTurn = max(t.lastTurn, e.order)
            map[e.path] = t
        }
        // 같은 순번이면 경로 오름차순으로 안정 정렬.
        return map.values.sorted { $0.lastTurn == $1.lastTurn ? $0.path < $1.path : $0.lastTurn > $1.lastTurn }
    }

    /// 표시용 짧은 경로 — 뒤 2~3 성분만.
    public static func shortPath(_ path: String, components: Int = 3) -> String {
        let comps = (path as NSString).pathComponents.filter { $0 != "/" }
        return comps.suffix(components).joined(separator: "/")
    }
}
