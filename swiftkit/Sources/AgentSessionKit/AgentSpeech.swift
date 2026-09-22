import Foundation

/// 세션에서 **말**을 가려낸다 — 파일을 몇 개 만졌나가 아니라 "무슨 말이 오갔나".
///
/// 실측(최근 세션 60개): `Bash` 1771 · `Edit` 205 · `Read` 143 회인데, 정작
/// `Agent`(서브에이전트 지시) 34 · `SendMessage`(에이전트끼리) 3 · `AskUserQuestion` 6 이다.
/// 그런데 화면에는 앞의 기계 소음만 보이고 뒤의 지시문은 사라졌다 — 툴 요약이 보는 키에
/// `prompt`·`message` 가 없었고, 요약이 **첫 줄만** 잘라 여러 줄 지시는 통째로 날아갔다.
///
/// 여기서 정하는 건 "어떤 툴 호출이 사실은 발화인가", 그리고 "그 발화 원문이 어디 있나".
public enum AgentSpeech {
    /// 발화의 성격 — 누구를 향한 말인가.
    public enum Kind: String, Sendable, Equatable {
        /// 서브에이전트를 띄우며 준 지시(`Agent`/`Task`).
        case dispatch
        /// 이미 도는 에이전트에게 보낸 말(`SendMessage`).
        case message
        /// 사람에게 던진 질문(`AskUserQuestion`).
        case question
        /// 불러온 스킬(`Skill`). 도구 호출 형태지만 "무엇을 근거로 일하는가" 라서
        /// Bash·Read 와 같은 소음으로 접으면 대화에서 사라진다 — 실측: 한 세션에
        /// 스킬 3회·지시 3회인데 지시만 보이고 스킬은 `도구 29 접힘` 에 묻혀 있었다.
        case skill
    }

    public struct Utterance: Sendable, Equatable {
        public let kind: Kind
        /// 수신자 — 서브에이전트 종류, 상대 에이전트 이름 등. 모르면 nil.
        public let recipient: String?
        /// 한 줄 요약(목록·접힘 상태에서 보여줄 것).
        public let headline: String
        /// **원문 그대로**. 지시문은 여러 줄이고, 잘라내면 "어떻게 말했나"가 사라진다.
        public let body: String

        public init(kind: Kind, recipient: String?, headline: String, body: String) {
            self.kind = kind
            self.recipient = recipient
            self.headline = headline
            self.body = body
        }
    }

    /// 툴 이름이 발화인지. 하네스마다 이름이 다르다(`Agent` · `Task`).
    public static func kind(toolName: String?) -> Kind? {
        switch (toolName ?? "").lowercased() {
        case "agent", "task": .dispatch
        case "sendmessage", "send_message": .message
        case "askuserquestion", "ask_user_question": .question
        case "skill": .skill
        default: nil
        }
    }

    /// 툴 입력에서 발화를 뽑는다. 순수 — 테스트 대상.
    public static func utterance(toolName: String?, input: Any?) -> Utterance? {
        guard let kind = kind(toolName: toolName) else { return nil }
        let dict = decoded(input)

        switch kind {
        case .dispatch:
            // prompt 가 본문이고 description 은 라벨이다. 예전엔 라벨만 남기고 본문을 버렸다.
            guard let prompt = string(dict?["prompt"]) else { return nil }
            let type = string(dict?["subagent_type"]) ?? string(dict?["agentType"])
            let label = string(dict?["description"]) ?? firstLine(prompt)
            return Utterance(kind: kind, recipient: type, headline: label, body: prompt)

        case .message:
            guard let text = string(dict?["message"]) ?? string(dict?["content"]) else { return nil }
            let to = string(dict?["to"]) ?? string(dict?["recipient"])
            return Utterance(kind: kind, recipient: to,
                             headline: string(dict?["summary"]) ?? firstLine(text), body: text)

        case .skill:
            // 스킬명이 곧 발화다. args 는 있을 때만 본문에 — 없으면 이름만으로 충분하다.
            guard let name = string(dict?["skill"]) ?? string(dict?["name"]) else { return nil }
            let args = string(dict?["args"]) ?? string(dict?["arguments"])
            return Utterance(kind: kind, recipient: name,
                             headline: args.map { "\(name) — \($0)" } ?? name,
                             body: args ?? name)

        case .question:
            // 질문은 배열로 온다 — 물어본 것 전부가 본문이다.
            let questions = (dict?["questions"] as? [[String: Any]] ?? [])
                .compactMap { string($0["question"]) }
            guard !questions.isEmpty else { return nil }
            return Utterance(kind: kind, recipient: nil,
                             headline: questions[0],
                             body: questions.enumerated()
                                .map { questions.count > 1 ? "\($0.offset + 1). \($0.element)" : $0.element }
                                .joined(separator: "\n"))
        }
    }

    // MARK: helpers

    /// codex 는 인자를 JSON **문자열**로 싣는다.
    static func decoded(_ input: Any?) -> [String: Any]? {
        if let d = input as? [String: Any] { return d }
        if let s = input as? String, let data = s.data(using: .utf8) {
            do {
                return try JSONSerialization.jsonObject(with: data) as? [String: Any]
            } catch {
                return nil
            }
        }
        return nil
    }

    static func string(_ v: Any?) -> String? {
        guard let s = v as? String else { return nil }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    static func firstLine(_ s: String, cap: Int = 80) -> String {
        let one = s.split(separator: "\n").first.map(String.init) ?? s
        return one.count > cap ? String(one.prefix(cap)) + "…" : one
    }
}
