import Foundation
import CommandKit
import InteropKit

/// `codex exec --sandbox {read-only|workspace-write}` 백엔드.
/// cardnews-gen CodexRunner / detailpage CodexSkillProvider 인자에서 정리.
/// stdin 입력은 ShellCommand 가 /dev/null 로 막으므로 prompt 는 argv 로.
public struct CodexBackend: LLMAgentBackend {
    public let backendID = "codex"
    public let executableOverride: String?
    public let sandbox: String

    public init(executableOverride: String? = nil, sandbox: String = "read-only") {
        self.executableOverride = executableOverride
        self.sandbox = sandbox
    }

    public func resolveExecutable() -> String? {
        #if os(iOS)
        nil
        #else
        if let exec = executableOverride { return exec }
        return resolveOnPATH("codex", extraCandidates: [HostPlatform.cliBinPath("codex"), "/usr/local/bin/codex"])
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
            shellQuote(exec), "exec",
            "--sandbox", sandbox,
            "--skip-git-repo-check",
            "--color", "never",
        ]
        if let m = request.agent.model { parts += ["--model", shellQuote(m)] }
        parts += [shellQuote(request.composedPrompt)]

        let result = ShellCommand.run(parts.joined(separator: " "),
                                      cwd: request.cwd,
                                      timeout: request.timeout ?? 600)
        if Self.isTimeoutExit(result.exitCode) {
            throw LLMBackendError.timeout(backend: backendID)
        }
        if result.exitCode != 0 {
            throw LLMBackendError.processExit(backend: backendID, exitCode: result.exitCode, stderr: result.stderr)
        }
        return LLMRunResult(text: result.trimmedStdout, isError: false, rawStdout: result.stdout)
        #endif
    }
}

extension CodexBackend {
    static func isTimeoutExit(_ code: Int32) -> Bool { code == 124 || code == 137 }
}
