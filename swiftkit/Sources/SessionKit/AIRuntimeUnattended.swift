import Foundation

/// 실행 도구를 무인(비대화)으로 한 번 부르는 방법 — 인자와 표준 입력.
public struct UnattendedRunPlan: Sendable, Equatable {
    /// 실행 파일 이름 뒤에 붙일 인자.
    public let arguments: [String]
    /// 표준 입력으로 넘길 프롬프트. 인자로 넘기는 도구는 nil.
    public let standardInput: String?

    public init(arguments: [String], standardInput: String?) {
        self.arguments = arguments
        self.standardInput = standardInput
    }
}

/// 실행 도구별 무인 실행 인자의 정본. 모델·추론 강도를 지정하고, 도구 실행·세션 저장을 끈다.
///
/// 인자 형식은 각 도구의 `--help` 로 확인한 것만 적는다(2026-10-04 이 Mac).
/// - Claude Code: `-p`(print) · `--model` · `--effort <low|medium|high|xhigh|max>` · `--output-format text` ·
///   `--no-session-persistence` · `--tools ""`(도구 끔). 프롬프트는 표준 입력.
/// - Codex: `exec` · `--skip-git-repo-check` · `--ephemeral` · `--sandbox read-only` · `--model` ·
///   `-c model_reasoning_effort="<e>"` · `-`(표준 입력에서 프롬프트).
/// - Grok: `--model` · `--reasoning-effort` · `--single <프롬프트>`(한 턴, 표준 출력).
/// - Antigravity·OpenCode·Cursor: 무인 실행 인자를 확인하지 않았다 — nil(지원 안 함).
extension SupportedAIAgentCLI {
    /// 무인 실행을 지원하는 도구인가.
    public var supportsUnattendedRun: Bool {
        unattendedRunPlan(prompt: "", model: nil, effort: nil) != nil
    }

    /// 이 도구가 받는 추론 강도 값. 목록 밖 값(`unknown` 등)은 인자로 넘기지 않는다.
    public var unattendedEffortValues: Set<String> {
        switch self {
        case .claude: ["low", "medium", "high", "xhigh", "max"]
        case .codex: ["minimal", "low", "medium", "high", "xhigh"]
        case .grok: ["low", "medium", "high"]
        case .agy, .opencode, .cursor: []
        }
    }

    /// 프롬프트 하나를 무인으로 돌리는 인자. 지원하지 않는 도구면 nil.
    public func unattendedRunPlan(prompt: String, model: String?, effort: String?) -> UnattendedRunPlan? {
        let model = model?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let effort = effort.flatMap { unattendedEffortValues.contains($0) ? $0 : nil }
        switch self {
        case .claude:
            var arguments = ["-p", "--output-format", "text", "--no-session-persistence", "--tools", ""]
            if let model { arguments += ["--model", model] }
            if let effort { arguments += ["--effort", effort] }
            return UnattendedRunPlan(arguments: arguments, standardInput: prompt)
        case .codex:
            var arguments = ["exec", "--skip-git-repo-check", "--ephemeral", "--sandbox", "read-only"]
            if let model { arguments += ["--model", model] }
            if let effort { arguments += ["-c", "model_reasoning_effort=\"\(effort)\""] }
            arguments.append("-")
            return UnattendedRunPlan(arguments: arguments, standardInput: prompt)
        case .grok:
            var arguments: [String] = []
            if let model { arguments += ["--model", model] }
            if let effort { arguments += ["--reasoning-effort", effort] }
            arguments += ["--single", prompt]
            return UnattendedRunPlan(arguments: arguments, standardInput: nil)
        case .agy, .opencode, .cursor:
            return nil
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
