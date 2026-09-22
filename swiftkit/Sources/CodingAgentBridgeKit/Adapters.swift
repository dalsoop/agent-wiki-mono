import Foundation

// MARK: - claude

/// `agent-room-terminal exec -- claude -p … --output-format json` — 스케줄 무상태 사이클 검증된 형태.
public struct ClaudeCodingAgentAdapter: CodingAgentAdapter {
    public init() {}
    public func arguments(for request: CodingAgentRequest) -> [String] {
        var args = [request.agent, "-p", request.prompt,
                    "--output-format", "json",
                    "--permission-mode", request.permissionMode,
                    "--setting-sources", "project,local"]
        if let model = request.model, !model.isEmpty { args += ["--model", model] }
        if let maxTurns = request.maxTurns { args += ["--max-turns", String(maxTurns)] }
        return args
    }
    public func parseMeta(_ output: String) -> (turns: Int?, cost: Double?) {
        guard let data = output.data(using: .utf8),
              let obj = CodingAgentJSON.object(from: data) else { return (nil, nil) }
        return (obj["num_turns"] as? Int, obj["total_cost_usd"] as? Double)
    }
    public func summarize(_ output: String, killed: Bool) -> String {
        CodingAgentSummary.flatten(output, resultKeys: ["result"], killed: killed)
    }
}

// MARK: - codex

/// `codex exec <prompt>` — 비대화형 exec 서브커맨드.
public struct CodexCodingAgentAdapter: CodingAgentAdapter {
    public init() {}
    public func arguments(for request: CodingAgentRequest) -> [String] {
        var args = [request.agent, "exec", request.prompt, "--skip-git-repo-check"]
        switch request.permissionMode {
        case "bypassPermissions":
            args.append("--dangerously-bypass-approvals-and-sandbox")
        case "plan", "readOnly":
            args += ["--sandbox", "read-only"]
        default:
            args.append("--full-auto")
        }
        if let model = request.model, !model.isEmpty { args += ["--model", model] }
        return args
    }
    public func parseMeta(_ output: String) -> (turns: Int?, cost: Double?) { (nil, nil) }
    public func summarize(_ output: String, killed: Bool) -> String {
        CodingAgentSummary.flatten(output, resultKeys: [], killed: killed)
    }
}

// MARK: - grok

/// `grok --single <prompt> --output-format json`.
public struct GrokCodingAgentAdapter: CodingAgentAdapter {
    public init() {}
    public func arguments(for request: CodingAgentRequest) -> [String] {
        var args = [request.agent, "--single", request.prompt, "--output-format", "json"]
        args += ["--permission-mode", request.permissionMode]
        if let model = request.model, !model.isEmpty { args += ["--model", model] }
        return args
    }
    public func parseMeta(_ output: String) -> (turns: Int?, cost: Double?) {
        guard let data = output.data(using: .utf8),
              let obj = CodingAgentJSON.object(from: data) else { return (nil, nil) }
        return (obj["num_turns"] as? Int, obj["total_cost_usd"] as? Double)
    }
    public func summarize(_ output: String, killed: Bool) -> String {
        CodingAgentSummary.flatten(output, resultKeys: ["result", "response", "content"], killed: killed)
    }
}

// MARK: - gemini

/// `gemini -p <prompt>`.
public struct GeminiCodingAgentAdapter: CodingAgentAdapter {
    public init() {}
    public func arguments(for request: CodingAgentRequest) -> [String] {
        var args = [request.agent, "-p", request.prompt]
        if let model = request.model, !model.isEmpty { args += ["--model", model] }
        return args
    }
    public func parseMeta(_ output: String) -> (turns: Int?, cost: Double?) { (nil, nil) }
    public func summarize(_ output: String, killed: Bool) -> String {
        CodingAgentSummary.flatten(output, resultKeys: [], killed: killed)
    }
}

// MARK: - script

/// 결정적 스크립트 — agent + scriptArgs 그대로.
public struct ScriptCodingAgentAdapter: CodingAgentAdapter {
    public init() {}
    public func arguments(for request: CodingAgentRequest) -> [String] {
        [request.agent] + (request.scriptArgs ?? [])
    }
    public func parseMeta(_ output: String) -> (turns: Int?, cost: Double?) { (nil, nil) }
    public func summarize(_ output: String, killed: Bool) -> String {
        CodingAgentSummary.flatten(output, resultKeys: [], killed: killed)
    }
}

// MARK: - generic

/// 모르는 CLI — 프롬프트를 위치 인자 하나.
public struct GenericCodingAgentAdapter: CodingAgentAdapter {
    public init() {}
    public func arguments(for request: CodingAgentRequest) -> [String] {
        [request.agent, request.prompt]
    }
    public func parseMeta(_ output: String) -> (turns: Int?, cost: Double?) { (nil, nil) }
    public func summarize(_ output: String, killed: Bool) -> String {
        CodingAgentSummary.flatten(output, resultKeys: [], killed: killed)
    }
}
