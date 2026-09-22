import Foundation

/// 대화에 **붙은 것**들. 발언(`message`)도 툴 호출도 아닌 `type:"attachment"` 줄에 온다.
///
/// 이 줄을 통째로 무시하고 있었다. 리더가 `user`/`assistant` 만 읽었기 때문인데, 실측
/// (2026-08-04, 최근 세션 15개 중 9개)으로 두 가지가 거기 있었다:
///
/// - `queued_command` — **사람이 친 말**. 18건. 화면상 사용자가 그 말을 한 적이 없는 게 됐다.
///   대화를 보는 화면에서 사람 말이 사라지는 건 다른 어떤 결함보다 나쁘다.
/// - `edited_text_file` — **대화에 붙은 파일**(경로 + 본문 일부). 73건, 그중 `.md` 18건.
///   "에이전트가 도구로 읽은 파일"과는 다른 축이다 — 이건 대화에 첨부된 문서다.
public enum SessionAttachment {
    case humanPrompt(String)
    case file(AttachedFile)

    /// attachment 줄에서 우리가 쓰는 것만 뽑는다. 나머지(스킬 목록·툴 목록·리마인더)는
    /// 시스템 잡음이라 의도적으로 버린다 — 그것까지 실으면 대화가 다시 잡음에 묻힌다.
    public static func parse(_ attachment: [String: Any]) -> SessionAttachment? {
        switch attachment["type"] as? String {
        case "queued_command":
            // origin.kind == human 인 것만. 자동 주입된 명령은 사람 말이 아니다.
            let origin = (attachment["origin"] as? [String: Any])?["kind"] as? String
            guard origin == nil || origin == "human",
                  let prompt = text(attachment["prompt"]) else { return nil }
            return .humanPrompt(prompt)

        case "edited_text_file":
            guard let path = text(attachment["filename"]) else { return nil }
            return .file(AttachedFile(path: path, snippet: text(attachment["snippet"])))

        default:
            return nil
        }
    }

    static func text(_ v: Any?) -> String? {
        guard let s = v as? String else { return nil }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

/// 대화에 붙은 파일 하나.
public struct AttachedFile: Sendable, Equatable {
    public let path: String
    /// 붙을 때 함께 실려 온 본문 일부(줄 번호가 붙어 있다). 없을 수도 있다.
    public let snippet: String?

    public init(path: String, snippet: String?) {
        self.path = path
        self.snippet = snippet
    }

    public var name: String { (path as NSString).lastPathComponent }

    /// 문서인가 — 목록에서 코드와 눈으로 갈라 보이게 하려고.
    public var isDocument: Bool {
        ["md", "markdown", "mdx", "txt", "rst", "adoc"]
            .contains((path as NSString).pathExtension.lowercased())
    }
}
