import Foundation

/// 서브에이전트·백그라운드 작업이 끝났다고 돌아오는 알림.
///
/// 하네스는 결과를 툴 리턴에 담지 않는다 — 지시(`Agent`) 직후의 리턴은
/// "Async agent launched successfully" 라는 내부 메타데이터뿐이고, **실제 산출물은 나중에
/// `<task-notification>` 블록으로 돌아온다**(`tool-use-id` 로 지시와 짝이 맞고,
/// `output-file` 에 본문이 있다).
///
/// 그런데 그 블록은 `<` 로 시작해서 "사람 발화가 아님" 필터에 걸려 **통째로 버려졌다**.
/// 그래서 화면에는 "무엇을 시켰나"만 남고 "그래서 어떻게 됐나"가 사라졌다.
public struct TaskNotice: Sendable, Equatable {
    public let taskId: String
    /// 이 알림이 응답하는 지시의 tool_use id — 지시 턴과 짝짓는 열쇠.
    public let toolUseId: String?
    public let status: String
    public let summary: String?
    /// 산출물 파일 경로. 있으면 그 자리에서 열어 볼 수 있다.
    public let outputFile: String?

    public init(taskId: String, toolUseId: String?, status: String,
                summary: String?, outputFile: String?) {
        self.taskId = taskId
        self.toolUseId = toolUseId
        self.status = status
        self.summary = summary
        self.outputFile = outputFile
    }

    public var succeeded: Bool { status.lowercased() == "completed" }

    /// `<task-notification>` 블록을 파싱. 아니면 nil. 순수 — 테스트 대상.
    public static func parse(_ text: String) -> TaskNotice? {
        guard text.contains("<task-notification>"), let taskId = field("task-id", in: text) else { return nil }
        return TaskNotice(taskId: taskId,
                          toolUseId: field("tool-use-id", in: text),
                          status: field("status", in: text) ?? "unknown",
                          summary: field("summary", in: text),
                          outputFile: field("output-file", in: text))
    }

    /// `<name>값</name>` 한 쌍. 값에 개행이 있어도 받는다.
    static func field(_ name: String, in text: String) -> String? {
        let open = "<\(name)>", close = "</\(name)>"
        guard let s = text.range(of: open),
              let e = text.range(of: close, range: s.upperBound..<text.endIndex) else { return nil }
        let v = text[s.upperBound..<e.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? nil : v
    }
}
