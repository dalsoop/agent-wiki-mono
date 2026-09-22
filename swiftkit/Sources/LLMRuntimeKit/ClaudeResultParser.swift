import Foundation

/// `agent-room-terminal exec -- claude -p --output-format json` 결과 스키마.
/// agent-of-gaya-swift ClaudeCodeAgentBot.swift 의 CLIResult 에서 끌어올린 정본.
public struct ClaudeCLIResult: Decodable, Equatable {
    public let result: String?
    public let session_id: String?
    public let is_error: Bool?
    public let num_turns: Int?
    public let total_cost_usd: Double?
}

/// claude stdout(JSON 또는 비JSON)을 LLMRunResult 로 해석.
public enum ClaudeResultParser {
    public static func parse(stdout: String, exitCode: Int32, stderr: String) -> LLMRunResult {
        let data = Data(stdout.utf8)
        if let cli = try? JSONDecoder().decode(ClaudeCLIResult.self, from: data) {
            let isError = cli.is_error ?? (exitCode != 0)
            return LLMRunResult(
                text: cli.result ?? stdout,
                sessionID: cli.session_id,
                isError: isError,
                numTurns: cli.num_turns,
                costUSD: cli.total_cost_usd,
                rawStdout: stdout
            )
        }
        // JSON 이 아니면 종료 코드로 에러 여부 판단, 원문을 텍스트로.
        let trimmed = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return LLMRunResult(
            text: trimmed.isEmpty && exitCode != 0 ? stderr : trimmed,
            isError: exitCode != 0,
            rawStdout: stdout
        )
    }
}
