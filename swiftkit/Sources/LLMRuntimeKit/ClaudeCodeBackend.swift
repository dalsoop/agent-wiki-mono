import Foundation
import CommandKit

/// `agent-room-terminal exec -- claude -p --output-format json` 백엔드.
/// PATH 보강(~/.claude/local, ~/.local/bin, ~/.npm-global/bin)은 agent-of-gaya ClaudeCodeAgentBot 과 정합.
public struct ClaudeCodeBackend: LLMAgentBackend {
    public let backendID = "claude"
    public let executableOverride: String?

    public init(executableOverride: String? = nil) {
        self.executableOverride = executableOverride
    }

    public func resolveExecutable() -> String? {
        #if os(iOS)
        nil
        #else
        if let exec = executableOverride { return exec }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let extras = [
            "\(home)/.claude/local/claude",
            "\(home)/.local/bin/claude",
            "\(home)/.npm-global/bin/claude",
        ]
        return resolveOnPATH("claude", extraCandidates: extras)
        #endif
    }

    public func run(_ request: LLMRunRequest) async throws -> LLMRunResult {
        #if os(iOS)
        throw LLMBackendError.notInstalled(backend: backendID)
        #else
        guard let exec = resolveExecutable() else {
            throw LLMBackendError.notInstalled(backend: backendID)
        }
        var parts: [String] = [
            shellQuote(exec), "-p", shellQuote(request.composedPrompt),
            "--output-format", "json",
        ]
        if let s = request.sessionID { parts += ["--resume", shellQuote(s)] }
        if let m = request.agent.model { parts += ["--model", shellQuote(m)] }
        if let p = request.agent.permissionMode { parts += ["--permission-mode", shellQuote(p)] }
        if let t = request.maxTurns { parts += ["--max-turns", "\(t)"] }

        let result = ShellCommand.run(parts.joined(separator: " "),
                                      cwd: request.cwd,
                                      timeout: request.timeout ?? 600)
        if Self.isTimeoutExit(result.exitCode) {
            throw LLMBackendError.timeout(backend: backendID)
        }
        return ClaudeResultParser.parse(stdout: result.stdout, exitCode: result.exitCode, stderr: result.stderr)
        #endif
    }
}

extension LLMAgentBackend where Self == ClaudeCodeBackend {
    /// 타임아웃으로 SIGKILL 된 exit code(true 면 timeout).
    static func isTimeoutExit(_ code: Int32) -> Bool { code == 124 || code == 137 }
}
