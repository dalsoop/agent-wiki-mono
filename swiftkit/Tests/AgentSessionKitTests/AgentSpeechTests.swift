import XCTest
@testable import AgentSessionKit

/// 기계 소음(Bash 1771건)과 말(Agent 34건)을 가르는 규칙. 말은 잘리면 안 된다 —
/// "어떻게 지시했나" 가 곧 내용이라 첫 줄만 남기면 아무것도 아니게 된다.
final class AgentSpeechTests: XCTestCase {
    private func toolTurn(_ name: String, _ input: String) -> TranscriptReader.Turn? {
        let line = #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"\#(name)","input":\#(input)}]}}"#
        return TranscriptReader.turns(text: line, tool: .claude).turns.first
    }

    func testDispatchKeepsWholePrompt() throws {
        let prompt = "첫 줄 지시\\n둘째 줄 제약\\n셋째 줄 산출물"
        let turn = try XCTUnwrap(toolTurn("Agent",
            #"{"description":"코드 조사","subagent_type":"Explore","prompt":"\#(prompt)"}"#))
        let speech = try XCTUnwrap(turn.speech)

        XCTAssertEqual(speech.kind, .dispatch)
        XCTAssertEqual(speech.recipient, "Explore")
        XCTAssertEqual(speech.headline, "코드 조사")
        // 핵심: 본문이 세 줄 그대로여야 한다.
        XCTAssertEqual(speech.body.split(separator: "\n").count, 3)
        XCTAssertTrue(speech.body.contains("셋째 줄 산출물"))
    }

    /// 예전엔 요약이 보는 키에 `message` 가 없어 화면에 "SendMessage" 글자만 남았다.
    func testAgentToAgentMessageSurvives() throws {
        let turn = try XCTUnwrap(toolTurn("SendMessage",
            #"{"to":"reviewer","message":"이 브랜치 리뷰해줘. 특히 동시성."}"#))
        let speech = try XCTUnwrap(turn.speech)

        XCTAssertEqual(speech.kind, .message)
        XCTAssertEqual(speech.recipient, "reviewer")
        XCTAssertTrue(speech.body.contains("동시성"))
        XCTAssertNotEqual(turn.text, "SendMessage")   // 이름만 남지 않는다
    }

    func testQuestionToHumanCollectsEveryQuestion() throws {
        let turn = try XCTUnwrap(toolTurn("AskUserQuestion",
            #"{"questions":[{"question":"A 로 갈까?"},{"question":"B 도 할까?"}]}"#))
        let speech = try XCTUnwrap(turn.speech)

        XCTAssertEqual(speech.kind, .question)
        XCTAssertTrue(speech.body.contains("A 로 갈까?"))
        XCTAssertTrue(speech.body.contains("B 도 할까?"))
    }

    /// 스킬은 "무엇을 근거로 일하는가" 다. 도구 호출 형태라 예전엔 Bash 와 같이 접혀
    /// 대화에서 사라졌다(실측: 한 세션 스킬 3회·지시 3회인데 지시만 보였다).
    func testSkillInvocationIsSpeech() throws {
        let turn = try XCTUnwrap(toolTurn("Skill", #"{"skill":"wiki-record"}"#))
        let speech = try XCTUnwrap(turn.speech)

        XCTAssertEqual(speech.kind, .skill)
        XCTAssertEqual(speech.recipient, "wiki-record")
        XCTAssertEqual(speech.headline, "wiki-record")
    }

    /// 인자가 있으면 "무슨 스킬을 어떻게 불렀나" 까지 남는다.
    func testSkillArgumentsBecomeBody() throws {
        let turn = try XCTUnwrap(toolTurn("Skill",
            #"{"skill":"agent-approval","args":"MR !3161 머지 승인요청"}"#))
        let speech = try XCTUnwrap(turn.speech)

        XCTAssertEqual(speech.recipient, "agent-approval")
        XCTAssertEqual(speech.body, "MR !3161 머지 승인요청")
        XCTAssertTrue(speech.headline.contains("agent-approval"))
    }

    /// 스킬명이 없으면 발화로 세우지 않는다 — 빈 줄이 대화에 끼면 소음이다.
    func testSkillWithoutNameIsNotSpeech() {
        XCTAssertNil(toolTurn("Skill", #"{}"#)?.speech)
    }

    /// 파일을 읽고 명령을 돌리는 건 말이 아니다 — 이게 섞이면 필터가 의미를 잃는다.
    func testMechanicalToolsAreNotSpeech() {
        XCTAssertNil(toolTurn("Bash", #"{"command":"ls -al"}"#)?.speech)
        XCTAssertNil(toolTurn("Read", #"{"file_path":"/a/b.md"}"#)?.speech)
        XCTAssertNil(AgentSpeech.kind(toolName: "Edit"))
    }

    /// codex 는 인자를 JSON 문자열로 싣는다 — 같은 말이 그쪽에서도 살아야 한다.
    func testCodexStringEncodedArgumentsParse() throws {
        let args = #"{\"subagent_type\":\"Plan\",\"prompt\":\"계획 세워줘\"}"#
        let line = #"{"type":"response_item","payload":{"type":"function_call","name":"Agent","arguments":"\#(args)"}}"#
        let turn = try XCTUnwrap(TranscriptReader.turns(text: line, tool: .codex).turns.first)
        XCTAssertEqual(turn.speech?.recipient, "Plan")
        XCTAssertEqual(turn.speech?.body, "계획 세워줘")
    }
}
