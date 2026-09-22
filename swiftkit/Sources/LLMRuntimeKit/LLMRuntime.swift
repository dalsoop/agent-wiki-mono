import Foundation
import CommandKit
import AgentRegistryKit
import InteropKit

/// LLM CLI 백엔드 실행 계층 — 흩어진 claude/codex/grok subprocess 호출을 하나의 런타임으로 통합.
///
/// 하위 계층은 이미 갖춰져 있다: AgentDef(어떤 백엔드·모델·권한·스킬), CommandKit(실행),
/// InteropKit(봉투), ClaudeLimitsKit(claude 한도). 이 Kit은 **실행·결과해석·디스패치**만 담당한다.

// MARK: - Request / Result / Error

public struct LLMRunRequest: Sendable {
    public var prompt: String
    public var agent: AgentDef
    public var cwd: String?
    public var sessionID: String?               // --resume
    public var maxTurns: Int?
    public var contextPreamble: String?         // 앱 도메인 컨텍스트(ResolvedAgent.promptPreamble 과 병합)
    public var timeout: TimeInterval?

    public init(prompt: String, agent: AgentDef, cwd: String? = nil, sessionID: String? = nil,
                maxTurns: Int? = nil, contextPreamble: String? = nil, timeout: TimeInterval? = nil) {
        self.prompt = prompt
        self.agent = agent
        self.cwd = cwd
        self.sessionID = sessionID
        self.maxTurns = maxTurns
        self.contextPreamble = contextPreamble
        self.timeout = timeout
    }

    /// 최종 프롬프트 = 컨텍스트 머리 + 사용자 입력.
    var composedPrompt: String {
        [contextPreamble, prompt].compactMap { $0 }.filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }
}

public struct LLMRunResult: Sendable, Equatable {
    public var text: String
    public var sessionID: String?
    public var isError: Bool
    public var numTurns: Int?
    public var costUSD: Double?
    public var rawStdout: String

    public init(text: String, sessionID: String? = nil, isError: Bool = false,
                numTurns: Int? = nil, costUSD: Double? = nil, rawStdout: String = "") {
        self.text = text
        self.sessionID = sessionID
        self.isError = isError
        self.numTurns = numTurns
        self.costUSD = costUSD
        self.rawStdout = rawStdout
    }
}

public enum LLMBackendError: Error, Equatable, Sendable, CustomStringConvertible {
    case notInstalled(backend: String)
    case invalidResponse(backend: String, message: String)
    case processExit(backend: String, exitCode: Int32, stderr: String)
    case timeout(backend: String)

    public var description: String {
        switch self {
        case let .notInstalled(b): return "\(b) backend not installed"
        case let .invalidResponse(b, m): return "\(b) invalid response: \(m)"
        case let .processExit(b, c, s): return "\(b) exited \(c): \(s)"
        case let .timeout(b): return "\(b) timed out"
        }
    }
}

// MARK: - Backend protocol

public protocol LLMAgentBackend: Sendable {
    var backendID: String { get }                   // "claude" | "codex" | "grok"
    func resolveExecutable() -> String?             // PATH/homebrew 에서 찾기, 없으면 nil
    func run(_ request: LLMRunRequest) async throws -> LLMRunResult
}

// MARK: - Runtime dispatch

/// AgentDef.agent 문자열 → 백엔드. 흩어진 engine/agent 디스패치를 일반화.
public struct LLMRuntime: Sendable {
    public init() {}

    public func backend(for agent: AgentDef) -> LLMAgentBackend {
        switch agent.agent.lowercased() {
        case "codex": return CodexBackend()
        case "grok": return GrokBackend()
        default: return ClaudeCodeBackend()
        }
    }

    /// 백엔드 발견 → 실행. 미설치 시 notInstalled.
    public func run(_ request: LLMRunRequest) async throws -> LLMRunResult {
        let backend = backend(for: request.agent)
        guard backend.resolveExecutable() != nil else {
            throw LLMBackendError.notInstalled(backend: backend.backendID)
        }
        return try await backend.run(request)
    }
}

// MARK: - Shared helpers

/// zsh -lc 안전 단일 인용.
func shellQuote(_ s: String) -> String {
    "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

/// PATH + homebrew/사용자 bin 후보에서 실행파일 탐색. 첫 hit 반환.
func resolveOnPATH(_ name: String, extraCandidates: [String] = []) -> String? {
    var candidates = extraCandidates
    if let path = ProcessInfo.processInfo.environment["PATH"] {
        candidates += path.split(separator: ":").map { "\($0)/\(name)" }
    }
    candidates += [HostPlatform.cliBinPath(name), "/usr/local/bin/\(name)"]
    let fm = FileManager.default
    return candidates.first { fm.isExecutableFile(atPath: $0) }
}
