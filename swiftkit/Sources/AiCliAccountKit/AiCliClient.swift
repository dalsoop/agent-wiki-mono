import Foundation
import StateRootKit

/// 관리 대상 AI CLI 클라이언트. `accounts.json` 의 `client` 필드 rawValue 정본이다.
///
/// 이 enum 이 정본인 이유: `accounts.json` 은 ai-cli-account-manager 가 쓰고
/// ai-cli-launcher 가 읽는 **앱 간 계약**이다. 양쪽이 각자 enum 을 들고 있으면
/// 한쪽만 케이스를 늘렸을 때 상대 앱이 조용히 계정을 누락한다.
///
/// UI 전용 속성(SF Symbol·틴트·아이콘 리소스명)은 여기 두지 않는다 — 표현은 앱 소관.
public enum AiCliClient: String, Sendable, Codable, CaseIterable, Identifiable {
    case claudeCode
    case codex
    case gemini
    case antigravity
    case opencode
    case grok
    case kiro
    case opencodex
    /// Cursor Agent CLI. 설치·전권한 정본은 AI Agent Configuration Manager
    /// (`cursor-setup` / `cursor-trust`). 이 케이스가 계정·런처 계약의 한 줄이다.
    case cursor

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex"
        case .gemini: return "Gemini CLI"
        case .antigravity: return "Antigravity"
        case .opencode: return "opencode"
        case .grok: return "Grok"
        case .kiro: return "Kiro CLI"
        case .opencodex: return "Open Codex"
        case .cursor: return "Cursor CLI"
        }
    }

    public var detail: String {
        switch self {
        case .claudeCode: return "Anthropic Claude Code CLI"
        case .codex: return "OpenAI Codex CLI"
        case .gemini: return "Google Gemini CLI"
        case .antigravity: return "Google Antigravity CLI (agy)"
        case .opencode: return "opencode (SST)"
        case .grok: return "xAI Grok Build TUI"
        case .kiro: return "Amazon Kiro CLI"
        case .opencodex: return "Open Codex (opencodex/ocx 멀티 프로바이더 프록시)"
        case .cursor: return "Cursor Agent CLI (cursor-agent)"
        }
    }

    /// 터미널에서 실행할 명령.
    public var command: String {
        switch self {
        case .claudeCode: return "claude"
        case .codex: return "codex"
        case .gemini: return "gemini"
        case .antigravity: return "agy"
        case .opencode: return "opencode"
        case .grok: return "grok"
        case .kiro: return "kiro-cli"
        // npm `open-codex`(ymichael/codex 포크)와 **다른 도구**다. 이 케이스는
        // `opencodex`/`ocx` 프록시(:10100)이고 소유 앱은 opencodex-account-manager.
        case .opencodex: return "opencodex"
        case .cursor: return "cursor-agent"
        }
    }

    /// `ai-cli-account-manager switch <client>` 인자.
    /// rawValue(`claudeCode`)와 CLI 인자(`claude`)가 다른 유일 케이스를 흡수한다.
    public var switchArgument: String {
        switch self {
        case .claudeCode: return "claude"
        default: return rawValue
        }
    }

    /// `ai-cli-account-manager <sub> config-dir <selector>` 의 서브커맨드.
    public var configDirSubcommand: String {
        switch self {
        case .claudeCode: return "claude-code"
        default: return rawValue
        }
    }

    /// 계정별 격리 실행에 쓰는 환경변수명.
    public var isolationEnvVar: String {
        switch self {
        case .claudeCode: return "CLAUDE_CONFIG_DIR"
        case .codex: return "CODEX_HOME"
        case .grok: return "GROK_HOME"
        case .gemini: return "GEMINI_CLI_HOME"
        case .antigravity: return "ANTIGRAVITY_HOME"
        case .opencode: return "XDG_DATA_HOME"
        case .kiro: return "KIRO_HOME"
        // opencodex 는 홈 override 를 지원하지 않는다(`~/.opencodex` 고정) — 격리 실행이
        // 막혀 있어(`supportsIsolatedLaunch == false`) 이 값은 실제로 쓰이지 않는
        // 자리표시자다. 지원이 생기면 실측한 변수명으로 바꿀 것.
        case .opencodex: return "OPENCODEX_HOME"
        // 홈 override 미실측 — 격리 실행은 끄고(`supportsIsolatedLaunch` 앱 쪽),
        // 자리표시자만 둔다. 공식 변수명이 확인되면 바꾼다.
        case .cursor: return "CURSOR_HOME"
        }
    }

    /// 활성 자격증명/OAuth 세션 파일 경로.
    public func credentialsPath(home: String = StateRootKit.path("")) -> String {
        switch self {
        case .claudeCode: return home + "/.claude/.credentials.json"
        case .codex: return home + "/.codex/auth.json"
        case .gemini: return home + "/.gemini/oauth_creds.json"
        case .antigravity: return home + "/.gemini/oauth_creds.json"
        case .opencode: return home + "/.local/share/opencode/auth.json"
        case .grok: return home + "/.grok/auth.json"
        case .kiro: return home + "/.kiro/credentials.json"
        // 정본 = `~/.opencodex/auth.json` (전부 소문자). opencodex-account-manager 의
        // `OcxPaths` 실측(`ocx status`)과 일치한다. 예전엔 `~/.codex/config.json`
        // (= Codex CLI 파일)을 돌려줘 Codex 자격을 ocx 자격으로 오귀속했다.
        case .opencodex: return home + "/.opencodex/auth.json"
        // cursor-agent FileAuth: darwin `~/.cursor/auth.json` (app name = "cursor").
        case .cursor: return home + "/.cursor/auth.json"
        }
    }

    /// "재인증"용 로그인 명령.
    public var loginCommand: String {
        switch self {
        case .claudeCode: return "claude"   // 앱/터미널 OAuth 로그인
        case .codex: return "codex login"
        case .gemini: return "gemini"       // 브라우저 OAuth
        case .antigravity: return "agy login"
        case .opencode: return "opencode auth login"
        case .grok: return "grok login"     // auth.x.ai OAuth (또는 --device-code)
        case .kiro: return "kiro-cli login"
        case .opencodex: return "opencodex login"  // 실제 호출은 provider 인자를 덧붙인다
        case .cursor: return "cursor-agent login"
        }
    }

    /// 다중 계정 추가 전 전역 자격을 비울 때 쓰는 로그아웃 명령.
    /// nil 이면 자격 파일을 백업 후 삭제한다. Claude Code 는 인앱 OAuth 로 별도 처리.
    public var logoutCommand: String? {
        switch self {
        case .grok: return "grok logout"
        case .codex: return "codex logout"
        case .opencode: return "opencode auth logout"
        case .kiro: return "kiro-cli logout"
        case .cursor: return "cursor-agent logout"
        case .gemini, .antigravity, .claudeCode, .opencodex: return nil
        }
    }

    /// 자격증명 파일을 통째로 교체하는 클라이언트인지.
    /// Claude Code 만 부분 병합(mcpOAuth 보존) 예외다.
    public var isFullSwap: Bool {
        self != .claudeCode
    }

    /// 서비스 종료 또는 비활성 클라이언트 여부.
    public var isRetired: Bool {
        false
    }

    /// UI 및 일반 전환에 노출할 활성 클라이언트 목록.
    public static var userFacingCases: [AiCliClient] {
        allCases.filter { !$0.isRetired }
    }
}

/// 계정 종류. OAuth 세션 스왑 vs env 기반 백엔드 프로파일.
/// `accounts.json` 의 `kind` 필드 rawValue 정본.
public enum AiCliAccountKind: String, Sendable, Codable, CaseIterable {
    case oauthSession
    case backendProfile
}

extension AiCliClient {
    /// opencodex 홈 디렉터리 (`~/.opencodex`) — auth.json·config.json 의 부모.
    ///
    /// 정본은 `credentialsPath(.opencodex)` 하나이고 나머지는 전부 여기서 유도한다.
    /// 예전엔 `credentialsPath`(`~/.codex/config.json`)·`ocxConfigPath`
    /// (`~/.opencodex/config.json`)·앱의 `~/.openCodex/auth.json` 이 따로 하드코딩돼
    /// 세 갈래로 갈렸다 — 유도로 바꿔 구조적으로 재발을 막는다.
    public func ocxHomeDir(home: String = StateRootKit.path("")) -> String {
        (AiCliClient.opencodex.credentialsPath(home: home) as NSString)
            .deletingLastPathComponent
    }

    /// opencodex config.json 경로 (auth.json 과 같은 디렉터리).
    public func ocxConfigPath(home: String = StateRootKit.path("")) -> String {
        (ocxHomeDir(home: home) as NSString).appendingPathComponent("config.json")
    }
}
