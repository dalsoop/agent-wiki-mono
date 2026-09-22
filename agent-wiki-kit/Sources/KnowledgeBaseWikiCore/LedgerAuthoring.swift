import Foundation
import StateRootKit

/// 저작 provenance — **이 객체를 무엇이 어떤 조건에서 썼나.**
///
/// `Provenance`(source) 와 다른 축이다. source 는 "내용이 어디서 왔나"(수집 원본·URL·
/// blob)이고, 여기는 "누가 어떤 런타임·비용으로 판단했나"다. 원장이 지금까지 author
/// 문자열 하나만 남겨서, 같은 `agent:claude@macbook` 이 어떤 모델로 얼마나 읽고 썼는지
/// 구분되지 않았다.
///
/// 왜 필요한가: 원장의 절반이 자동 분류·이주 배치(import-classifier 222 ·
/// taxonomy-drafter 202 ·wiki-maintainer 418)다. 그 판단들이 어떤 조건에서 나왔는지
/// 남지 않으면, 나중에 "이 분류를 믿어도 되나"를 판정할 근거가 없다. 사용자가 요구한
/// 것도 정확히 이것이다 — 작성 에이전트의 토큰 사용량과 쌓여 있던 컨텍스트.
///
/// 정직성 규약: **아는 것만 채운다.** CLI 는 토큰 수를 스스로 알 수 없다(하네스만 안다).
/// 그래서 전 필드 선택이고, 화면은 비어 있으면 "기록 없음"이라고 그대로 말한다.
/// 없는 값을 0 으로 채워 "0 토큰으로 썼다"는 거짓을 만들지 않는다.
public struct Authoring: Sendable, Equatable {
    public var runtime: String?      // claude-code | codex | grok | app | human …
    public var model: String?        // claude-opus-5 · gpt-… — 같은 author 라도 모델이 다르다
    public var session: String?      // 하네스 세션 id — 원 대화로 되짚는 실마리
    public var tokensIn: Int?        // 입력 토큰(하네스가 알 때만)
    public var tokensOut: Int?       // 출력 토큰
    public var contextObjects: Int?  // 쓰기 전에 읽은 원장 객체 수 — "무엇 위에서 판단했나"의 크기
    public var host: String?         // 어느 기기에서

    public init(runtime: String? = nil, model: String? = nil, session: String? = nil,
                tokensIn: Int? = nil, tokensOut: Int? = nil,
                contextObjects: Int? = nil, host: String? = nil) {
        self.runtime = runtime; self.model = model; self.session = session
        self.tokensIn = tokensIn; self.tokensOut = tokensOut
        self.contextObjects = contextObjects; self.host = host
    }

    public var isEmpty: Bool {
        runtime == nil && model == nil && session == nil
            && tokensIn == nil && tokensOut == nil && contextObjects == nil && host == nil
    }

    /// 환경에서 읽을 수 있는 만큼 채운다. 하네스가 심어 주는 변수만 본다 —
    /// 없으면 없는 대로 둔다(추측해서 채우면 그게 곧 거짓 기록이다).
    public static func fromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Authoring {
        func text(_ keys: String...) -> String? {
            for key in keys {
                if let value = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !value.isEmpty { return value }
            }
            return nil
        }
        func number(_ keys: String...) -> Int? {
            for key in keys {
                if let value = environment[key], let n = Int(value.trimmingCharacters(in: .whitespaces)) {
                    return n
                }
            }
            return nil
        }
        return Authoring(
            runtime: text("AGENT_WIKI_RUNTIME", "CLAUDE_CODE", "CODEX_RUNTIME"),
            model: text("AGENT_WIKI_MODEL", "ANTHROPIC_MODEL", "CODEX_MODEL"),
            session: text("AGENT_WIKI_SESSION", "CLAUDE_SESSION_ID", "CODEX_SESSION_ID"),
            tokensIn: number("AGENT_WIKI_TOKENS_IN"),
            tokensOut: number("AGENT_WIKI_TOKENS_OUT"),
            contextObjects: number("AGENT_WIKI_CONTEXT_OBJECTS"),
            host: text("AGENT_WIKI_HOST") ?? ProcessInfo.processInfo.hostName)
    }

    /// 하네스가 남겨둔 세션 파일. 환경변수는 셸을 건너뛰는 호출(앱·훅)에 안 실리고,
    /// Claude Code 같은 하네스는 훅 stdin 으로만 세션·모델을 알려준다. 그래서 훅이
    /// 이 파일에 적어두고 CLI 가 발행할 때 읽는다.
    public static var ambientPath: URL {
        StateRootKit.url(".agent-wiki/authoring.json")
    }

    /// 지금 이 실행의 저작 조건 — **환경변수가 세션 파일을 이긴다.**
    /// 명시적으로 넘긴 값이 배경값보다 우선해야, 배치 작업이 자기 조건을 정확히 남길 수 있다.
    public static func ambient(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileURL: URL? = nil
    ) -> Authoring {
        let env = fromEnvironment(environment)
        guard let data = try? Data(contentsOf: fileURL ?? ambientPath),
              let file = Authoring(jsonLine: String(decoding: data, as: UTF8.self))
        else { return env }
        return Authoring(
            runtime: env.runtime ?? file.runtime,
            model: env.model ?? file.model,
            session: env.session ?? file.session,
            tokensIn: env.tokensIn ?? file.tokensIn,
            tokensOut: env.tokensOut ?? file.tokensOut,
            contextObjects: env.contextObjects ?? file.contextObjects,
            host: env.host ?? file.host)
    }

    /// `{json}` 한 줄 — 키 순서 고정으로 결정적. 값 없는 키는 생략.
    public var jsonLine: String? {
        if isEmpty { return nil }
        var parts: [String] = []
        func addText(_ k: String, _ v: String?) {
            guard let v, !v.isEmpty else { return }
            let escaped = v.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            parts.append("\"\(k)\":\"\(escaped)\"")
        }
        func addNumber(_ k: String, _ v: Int?) {
            guard let v else { return }
            parts.append("\"\(k)\":\(v)")
        }
        addNumber("contextObjects", contextObjects)
        addText("host", host)
        addText("model", model)
        addText("runtime", runtime)
        addText("session", session)
        addNumber("tokensIn", tokensIn)
        addNumber("tokensOut", tokensOut)
        return parts.isEmpty ? nil : "{" + parts.joined(separator: ",") + "}"
    }

    public init?(jsonLine: String?) {
        guard let jsonLine, let data = jsonLine.data(using: .utf8) else { return nil }
        let obj: [String: Any]
        do {
            guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            obj = parsed
        } catch {
            return nil
        }
        guard !obj.isEmpty else { return nil }
        func text(_ k: String) -> String? { obj[k] as? String }
        func number(_ k: String) -> Int? {
            if let n = obj[k] as? Int { return n }
            if let n = obj[k] as? NSNumber { return n.intValue }
            return nil
        }
        self.init(runtime: text("runtime"), model: text("model"), session: text("session"),
                  tokensIn: number("tokensIn"), tokensOut: number("tokensOut"),
                  contextObjects: number("contextObjects"), host: text("host"))
    }

    /// 사람이 읽는 한 줄 — 화면·CLI 공용. 비어 있으면 그렇다고 말한다.
    public var summary: String {
        guard !isEmpty else { return "기록 없음" }
        var parts: [String] = []
        if let model { parts.append(model) }
        else if let runtime { parts.append(runtime) }
        if let tokensIn, let tokensOut { parts.append("토큰 \(tokensIn)→\(tokensOut)") }
        else if let tokensOut { parts.append("출력 \(tokensOut) 토큰") }
        if let contextObjects { parts.append("컨텍스트 \(contextObjects)객체") }
        if let host { parts.append(host) }
        return parts.isEmpty ? "기록 없음" : parts.joined(separator: " · ")
    }
}
