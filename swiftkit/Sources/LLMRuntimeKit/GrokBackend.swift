import Foundation
import CommandKit

/// Grok Build CLI의 headless 단일 실행(`grok --single … --output-format plain`) 백엔드.
public struct GrokBackend: LLMAgentBackend {
    public let backendID = "grok"
    public let executableOverride: String?

    public init(executableOverride: String? = nil) {
        self.executableOverride = executableOverride
    }

    public func resolveExecutable() -> String? {
        #if os(iOS)
        nil
        #else
        if let exec = executableOverride { return exec }
        return resolveOnPATH("grok")
        #endif
    }

    public func run(_ request: LLMRunRequest) async throws -> LLMRunResult {
        #if os(iOS)
        throw LLMBackendError.notInstalled(backend: backendID)
        #else
        guard let exec = resolveExecutable() else {
            throw LLMBackendError.notInstalled(backend: backendID)
        }
        var parts = [
            shellQuote(exec),
            "--single", shellQuote(request.composedPrompt),
            "--output-format", "plain",
            "--no-alt-screen",
        ]
        if let session = request.sessionID {
            parts += ["--resume", shellQuote(session)]
        }
        if let model = request.agent.model {
            parts += ["--model", shellQuote(model)]
        }
        if let mode = request.agent.permissionMode {
            parts += ["--permission-mode", shellQuote(mode)]
        }
        if let turns = request.maxTurns {
            parts += ["--max-turns", String(turns)]
        }
        let result = ShellCommand.run(
            parts.joined(separator: " "),
            cwd: request.cwd,
            timeout: request.timeout ?? 600)
        if Self.isTimeoutExit(result.exitCode) {
            throw LLMBackendError.timeout(backend: backendID)
        }
        guard result.exitCode == 0 else {
            throw LLMBackendError.processExit(
                backend: backendID,
                exitCode: result.exitCode,
                stderr: result.stderr)
        }
        return LLMRunResult(
            text: result.trimmedStdout,
            isError: false,
            rawStdout: result.stdout)
        #endif
    }
}

extension GrokBackend {
    static func isTimeoutExit(_ code: Int32) -> Bool { code == 124 || code == 137 }
}
