import Foundation

/// 한 번의 편집이 **무엇을 무엇으로** 바꿨나.
///
/// 목록에서 파일을 눌러도 지금 내용만 보였다 — "이 에이전트가 뭘 바꿨나"는 못 봤다.
/// git 워킹트리 diff 로는 답이 안 된다: 이미 커밋됐거나, 여러 에이전트가 같은 파일을
/// 만졌거나, 되돌려진 편집은 워킹트리에 흔적이 없다. 그 에이전트가 실제로 친 편집은
/// 세션 기록에만 있다.
public struct EditHunk: Sendable, Equatable, Identifiable {
    public let path: String
    /// 바꾸기 전. 새 파일 생성(Write)이면 빈 문자열.
    public let before: String
    /// 바꾼 후.
    public let after: String
    /// 세션 안 등장 순번 — 최근 편집을 위로 놓는 기준.
    public let order: Int

    public var id: String { "\(path)#\(order)" }
    /// 파일을 새로 쓴 편집인지(이전 내용이 없다).
    public var isCreation: Bool { before.isEmpty }

    public init(path: String, before: String, after: String, order: Int) {
        self.path = path
        self.before = before
        self.after = after
        self.order = order
    }
}

public enum EditHunks {
    /// 툴 입력에서 편집 내용을 뽑는다. 편집이 아니면 빈 배열. 순수 — 테스트 대상.
    ///
    /// 다루는 모양:
    /// - `Edit`      — `old_string` → `new_string`
    /// - `MultiEdit` — `edits[]` 안에 같은 쌍이 여럿
    /// - `Write`     — `content` 만(생성)
    public static func hunks(toolName: String?, input: Any?, order: Int) -> [EditHunk] {
        let name = (toolName ?? "").lowercased()
        guard let dict = AgentSpeech.decoded(input) else { return [] }

        switch name {
        case "edit":
            guard let path = AgentSpeech.string(dict["file_path"]) else { return [] }
            return [EditHunk(path: path,
                             before: (dict["old_string"] as? String) ?? "",
                             after: (dict["new_string"] as? String) ?? "",
                             order: order)]

        case "multiedit":
            guard let path = AgentSpeech.string(dict["file_path"]) else { return [] }
            return (dict["edits"] as? [[String: Any]] ?? []).map {
                EditHunk(path: AgentSpeech.string($0["file_path"]) ?? path,
                         before: ($0["old_string"] as? String) ?? "",
                         after: ($0["new_string"] as? String) ?? "",
                         order: order)
            }

        case "write":
            guard let path = AgentSpeech.string(dict["file_path"]),
                  let content = dict["content"] as? String else { return [] }
            return [EditHunk(path: path, before: "", after: content, order: order)]

        default:
            return []
        }
    }

    /// 발언 목록에서 한 파일의 편집만, **최근 것 먼저**.
    public static func forFile(_ path: String, turns: [TranscriptReader.Turn]) -> [EditHunk] {
        turns.flatMap(\.editHunks).filter { $0.path == path }.sorted { $0.order > $1.order }
    }

    /// 아주 단순한 줄 단위 대조 — 양쪽에 공통으로 있는 줄은 문맥, 나머지는 추가/삭제.
    /// 외부 diff 라이브러리를 들이지 않는다(이 저장소는 외부 의존을 늘리지 않는다).
    /// 정교한 최소 편집거리가 아니라 **눈으로 확인 가능한 대조**가 목적이다.
    public static func lineDiff(before: String, after: String) -> [(kind: LineKind, text: String)] {
        let old = before.isEmpty ? [] : before.components(separatedBy: "\n")
        let new = after.isEmpty ? [] : after.components(separatedBy: "\n")
        let oldSet = Set(old), newSet = Set(new)

        var out: [(LineKind, String)] = []
        for line in old where !newSet.contains(line) { out.append((.removed, line)) }
        for line in new {
            out.append((oldSet.contains(line) ? .context : .added, line))
        }
        return out
    }

    public enum LineKind: Sendable, Equatable { case context, added, removed }
}
