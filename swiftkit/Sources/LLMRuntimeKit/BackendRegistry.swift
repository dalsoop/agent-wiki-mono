import Foundation

/// 설치된 LLM 백엔드 목록(PATH 스캔). ai-cli-account-manager 와 협력 가능 —
/// 계정/로그인 상태는 그 앱 소유, 여기는 실행파일 존재만 판정.
public struct BackendRegistry: Sendable {
    public init() {}

    public struct Entry: Sendable, Equatable {
        public let id: String        // "claude" | "codex" | "grok"
        public let path: String

        public init(id: String, path: String) {
            self.id = id
            self.path = path
        }
    }

    public func scan() -> [Entry] {
        let backends: [LLMAgentBackend] = [ClaudeCodeBackend(), CodexBackend(), GrokBackend()]
        return backends.compactMap { b in
            guard let path = b.resolveExecutable() else { return nil }
            return Entry(id: b.backendID, path: path)
        }
    }

    public func installed() -> [String] { scan().map { $0.id } }
    public func isInstalled(_ id: String) -> Bool { installed().contains(id) }
}
