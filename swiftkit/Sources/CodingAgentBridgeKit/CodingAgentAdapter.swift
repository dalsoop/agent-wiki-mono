import Foundation

/// 코딩 에이전트 CLI 어댑터 — 구독제 CLI마다 플래그 문법·출력 형식이 달라
/// 같은 `CodingAgentRequest` 를 CLI 별 인자·파서로 번역한다.
///
/// 전부 로컬 로그인 세션(구독) 전제 — API 키 불요. 새 CLI 는 어댑터 하나 추가.
public protocol CodingAgentAdapter: Sendable {
    /// 실행 인자(첫 요소 = 실행 파일 이름/경로, 보통 `/usr/bin/env` 로 실행).
    func arguments(for request: CodingAgentRequest) -> [String]
    /// 출력에서 관측 메타(턴 수·비용) 추출. 형식이 없으면 (nil, nil).
    func parseMeta(_ output: String) -> (turns: Int?, cost: Double?)
    /// 출력 요약(한 줄, 200자) — 실행 이력·stuck 감지 재료.
    func summarize(_ output: String, killed: Bool) -> String
}

public enum CodingAgentAdapterRegistry {
    public static func adapter(for request: CodingAgentRequest) -> any CodingAgentAdapter {
        switch CodingAgentKind.resolve(agentBaseName: request.agentBaseName, isScript: request.isScript) {
        case .claude: return ClaudeCodingAgentAdapter()
        case .codex: return CodexCodingAgentAdapter()
        case .grok: return GrokCodingAgentAdapter()
        case .gemini: return GeminiCodingAgentAdapter()
        case .script: return ScriptCodingAgentAdapter()
        case .generic: return GenericCodingAgentAdapter()
        }
    }

    public static func adapter(kind: CodingAgentKind) -> any CodingAgentAdapter {
        switch kind {
        case .claude: return ClaudeCodingAgentAdapter()
        case .codex: return CodexCodingAgentAdapter()
        case .grok: return GrokCodingAgentAdapter()
        case .gemini: return GeminiCodingAgentAdapter()
        case .script: return ScriptCodingAgentAdapter()
        case .generic: return GenericCodingAgentAdapter()
        }
    }
}

// MARK: - 공용 요약

enum CodingAgentSummary {
    static func flatten(_ output: String, resultKeys: [String], killed: Bool) -> String {
        if killed { return "워치독에 끊김(무한 매달림)" }
        if let data = output.data(using: .utf8),
           let obj = CodingAgentJSON.object(from: data) {
            for key in resultKeys {
                if let result = obj[key] as? String {
                    return String(result.replacingOccurrences(of: "\n", with: " ").prefix(200))
                }
            }
        }
        let flat = output.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        return flat.isEmpty ? "(출력 없음)" : String(flat.prefix(200))
    }
}
