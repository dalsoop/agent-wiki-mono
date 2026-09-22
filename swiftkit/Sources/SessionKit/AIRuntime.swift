import Foundation

/// AI CLI runtimes whose local sessions are understood by SessionKit.
///
/// Keep product-facing identity here so every app uses the same spelling,
/// executable name, storage root, and resume contract.
public enum SupportedAIAgentCLI: String, CaseIterable, Codable, Sendable, Hashable {
    case claude
    case codex
    case grok
    case agy
    case opencode
    case cursor

    public var displayName: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        case .grok: "Grok"
        case .agy: "Antigravity"
        case .opencode: "OpenCode"
        case .cursor: "Cursor"
        }
    }

    public var executableName: String {
        switch self {
        case .cursor: "cursor-agent"
        default: rawValue
        }
    }

    /// PATH 에서 찾을 실행 파일 이름 (executableName 과 동일).
    public var executable: String { executableName }

    /// 상태(세션 저장소) 디렉터리. 대부분 `~/.<runtime>` 이지만 Antigravity 는
    /// CLI 실행 파일이 `agy` 인데 데이터는 Gemini 계열 경로에 둔다(실측 2026-09-01).
    public var defaultStateDirectoryName: String {
        switch self {
        case .claude, .codex, .grok, .opencode, .cursor: ".\(rawValue)"
        case .agy: ".gemini/antigravity-cli"
        }
    }

    /// 붙여넣기·네이티브 재개가 같이 읽는 문법. 첫 원소가 `resumeArguments` 의 정본이다.
    public var resumeTokens: [ResumeToken] {
        switch self {
        case .claude: [.flag("--resume"), .flag("-r")]
        case .codex: [.subcommand("resume")]
        case .grok: [.flag("--resume")]
        case .agy: [.flag("--conversation")]
        case .opencode: [.flag("--session")]
        case .cursor: [.flag("--resume")]
        }
    }

    public func resumeArguments(sessionID: String) -> [String] {
        switch resumeTokens[0] {
        case .flag(let flag): [flag, sessionID]
        case .subcommand(let name): [name, sessionID]
        }
    }

    /// help·usage 에 박던 `claude|codex|grok` 복붙의 정본.
    public static var helpPipe: String {
        allCases.map(\.rawValue).joined(separator: "|")
    }

    /// 본문 나열에 박던 `claude/codex/grok` 복붙의 정본.
    public static var helpSlash: String {
        allCases.map(\.rawValue).joined(separator: "/")
    }
}

/// 하위 호환성을 위한 typealias
public typealias AIRuntime = SupportedAIAgentCLI
public typealias AgentTool = SupportedAIAgentCLI

/// 런타임 재개 한 토큰. 플래그(`--resume`)와 서브커맨드(`resume`)를 구분한다.
public enum ResumeToken: Equatable, Sendable {
    case flag(String)
    case subcommand(String)
}

