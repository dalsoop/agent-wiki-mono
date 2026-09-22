import Foundation
import CommandKit

/// LLM CLI 명령행 조합 유틸리티 — raw 프로세스/셸 문자열 조립의 단일 정본.
public enum LLMCommandBuilder {
    public static func launchCommand(backend: String, model: String? = nil, permissionMode: String? = nil) -> String {
        switch backend.lowercased() {
        case "codex":
            return "exec codex"
        case "grok":
            return "exec grok"
        default:
            var parts = ["exec claude"]
            if let model, !model.isEmpty { parts.append("--model \(shellQuote(model))") }
            if let permissionMode, !permissionMode.isEmpty { parts.append("--permission-mode \(shellQuote(permissionMode))") }
            return parts.joined(separator: " ")
        }
    }

    public static func resumeCommand(
        backend: String,
        sessionID: String,
        prompt: String? = nil,
        permissionMode: String? = nil,
        outputFormat: String? = nil
    ) -> String {
        let q = shellQuote
        switch backend.lowercased() {
        case "codex":
            if let prompt, !prompt.isEmpty {
                return "codex exec resume \(q(sessionID)) \(q(prompt))"
            }
            return "codex resume \(q(sessionID))"
        case "grok":
            if let prompt, !prompt.isEmpty {
                return "grok --resume \(q(sessionID)) -p \(q(prompt))"
            }
            return "exec grok --resume \(q(sessionID))"
        default: // claude
            var parts = ["claude", "--resume", q(sessionID)]
            if let prompt, !prompt.isEmpty {
                parts += ["-p", q(prompt)]
            }
            if let permissionMode, !permissionMode.isEmpty {
                parts += ["--permission-mode", q(permissionMode)]
            }
            if let outputFormat, !outputFormat.isEmpty {
                parts += ["--output-format", q(outputFormat)]
            }
            return parts.joined(separator: " ")
        }
    }
}
