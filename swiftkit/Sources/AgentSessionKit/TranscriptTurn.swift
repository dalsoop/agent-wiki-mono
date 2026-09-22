import Foundation

extension TranscriptReader {
    public struct Turn: Sendable, Equatable, Identifiable {
        /// 소비 뷰들의 **합집합**이다 — 각자 필요한 만큼 좁혀 쓴다(전사본 뷰는 tool/result 를
        /// 한 종류로 합치고, 꼬리 미리보기는 나눠 본다).
        public enum Role: String, Sendable, Equatable {
            case user, assistant, thinking, tool, toolResult
        }

        public struct Details: Sendable, Equatable {
            public var toolName: String?
            public var filePaths: [String]
            public var speech: AgentSpeech.Utterance?
            public var toolUseId: String?
            public var notice: TaskNotice?
            public var editHunks: [EditHunk]
            public var attachedFile: AttachedFile?

            public init(
                toolName: String? = nil,
                filePaths: [String] = [],
                speech: AgentSpeech.Utterance? = nil,
                toolUseId: String? = nil,
                notice: TaskNotice? = nil,
                editHunks: [EditHunk] = [],
                attachedFile: AttachedFile? = nil
            ) {
                self.toolName = toolName
                self.filePaths = filePaths
                self.speech = speech
                self.toolUseId = toolUseId
                self.notice = notice
                self.editHunks = editHunks
                self.attachedFile = attachedFile
            }
        }

        public var id: Int
        public var role: Role
        public var text: String
        public var toolName: String?
        /// 이 발언이 **건드린 파일 경로**(툴 호출에만). 요약 문자열에서 경로를 다시 긁어내는
        /// 소비처가 여럿 생겨서(각자 정규식으로) 여기서 한 번만 뽑아 실어 보낸다.
        public var filePaths: [String]
        /// 이 호출이 사실은 **발화**일 때 그 원문(서브에이전트 지시·에이전트 간 메시지·
        /// 사람에게 던진 질문). 기계 소음과 말을 가르는 신호라 잘라내지 않고 싣는다.
        public var speech: AgentSpeech.Utterance?
        /// 이 툴 호출의 id — 나중에 돌아오는 완료 알림과 짝짓는 열쇠.
        public var toolUseId: String?
        /// 서브에이전트·백그라운드 작업 완료 알림(있으면 이 턴이 그 결과다).
        public var notice: TaskNotice?
        /// 이 편집이 무엇을 무엇으로 바꿨나(Edit/MultiEdit/Write 일 때만).
        public var editHunks: [EditHunk]
        /// 대화에 **붙은 파일**(첨부). 도구로 읽은 파일과는 다른 축이다.
        public var attachedFile: AttachedFile?
        public var at: Date?

        public init(
            id: Int,
            role: Role,
            text: String,
            details: Details = .init(),
            at: Date? = nil
        ) {
            self.id = id
            self.role = role
            self.text = text
            self.toolName = details.toolName
            self.filePaths = details.filePaths
            self.speech = details.speech
            self.toolUseId = details.toolUseId
            self.notice = details.notice
            self.editHunks = details.editHunks
            self.attachedFile = details.attachedFile
            self.at = at
        }
    }

    public struct Options: Sendable, Equatable {
        /// 발언 상한. 넘으면 `truncated`.
        public var maxTurns: Int
        /// 에이전트의 사고 과정(thinking/reasoning)을 담을지. 뷰에 따라 다르다.
        public var includeThinking: Bool
        /// 툴 호출·결과를 담을지.
        public var includeTools: Bool
        /// 툴 결과 한 줄의 길이 상한.
        public var toolTextCap: Int

        public init(maxTurns: Int = 600, includeThinking: Bool = true,
                    includeTools: Bool = true, toolTextCap: Int = 400) {
            self.maxTurns = maxTurns
            self.includeThinking = includeThinking
            self.includeTools = includeTools
            self.toolTextCap = toolTextCap
        }
    }

    /// grok `streaming-messages-json` 한 런의 메타. 발언 Role 이 아니라 결과 줄이다.
    public struct GrokStreamMeta: Sendable, Equatable {
        public var sessionId: String?
        public var model: String?
        public var cwd: String?
        public var resultSubtype: String?
        public var numTurns: Int?
        public var durationMs: Int?
        public var totalCostUsd: Double?

        public init(
            sessionId: String? = nil,
            model: String? = nil,
            cwd: String? = nil,
            resultSubtype: String? = nil,
            numTurns: Int? = nil,
            durationMs: Int? = nil,
            totalCostUsd: Double? = nil
        ) {
            self.sessionId = sessionId
            self.model = model
            self.cwd = cwd
            self.resultSubtype = resultSubtype
            self.numTurns = numTurns
            self.durationMs = durationMs
            self.totalCostUsd = totalCostUsd
        }
    }

    public struct Parsed: Sendable, Equatable {
        public var turns: [Turn]
        public var truncated: Bool
        public var grokStream: GrokStreamMeta?

        public init(turns: [Turn], truncated: Bool, grokStream: GrokStreamMeta? = nil) {
            self.turns = turns
            self.truncated = truncated
            self.grokStream = grokStream
        }
    }

    /// 라이브 follow. `consumedOffset` 은 온전한 줄(개행으로 끝난)까지만 소비한 바이트다.
    public struct Appended: Sendable, Equatable {
        public var turns: [Turn]
        public var consumedOffset: Int
        public var truncated: Bool
        public var grokStream: GrokStreamMeta?

        public init(
            turns: [Turn],
            consumedOffset: Int,
            truncated: Bool,
            grokStream: GrokStreamMeta? = nil
        ) {
            self.turns = turns
            self.consumedOffset = consumedOffset
            self.truncated = truncated
            self.grokStream = grokStream
        }
    }
}
