import Foundation
import AgentSessionKit
import SkillRegistryKit
import StateRootKit

/// 이 앱의 진입점 — 세션 발견 → 컨텍스트 카드 → 문서 역방향 집계.
public struct Ledger: Sendable {
    public let resolver: ContextResolver
    public let launchStore: LaunchStore
    public let docIndexCache: DocIndexCache
    public let activationIndexCache: ActivationIndexCache
    public let home: String

    public init(home: String = StateRootKit.root, launchStore: LaunchStore? = nil,
                docIndexCache: DocIndexCache? = nil,
                activationIndexCache: ActivationIndexCache? = nil) {
        self.home = home
        self.resolver = ContextResolver(home: home)
        self.launchStore = launchStore ?? LaunchStore(root: StateRootKit.path(".agent-session-context-ledger", homeDirectory: home))
        self.docIndexCache = docIndexCache
            ?? DocIndexCache(root: StateRootKit.path(".agent-session-context-ledger/doc-index", homeDirectory: home))
        self.activationIndexCache = activationIndexCache
            ?? ActivationIndexCache(root: StateRootKit.path(".agent-session-context-ledger/activation-index", homeDirectory: home))
    }

    /// 홈에 실제로 있는 전역 스킬 루트. 도구 목록은 SkillRegistryKit `globalDefaults`.
    public func defaultSkillRoots() -> [String] {
        SkillRegistry(home: URL(fileURLWithPath: home)).existingGlobalRootPaths()
    }

    func digest(_ ref: SessionRef) -> SessionDigest {
        switch ref.tool {
        case .claude: return ClaudeSessionReader().digest(ref)
        case .codex: return CodexSessionReader().digest(ref)
        case .grok: return GrokSessionReader().digest(ref)
        case .agy: return AntigravitySessionReader().digest(ref)
        case .opencode, .cursor: return SessionDigest(ref: ref)
        }
    }

    /// 순회에서 잘라낼 디렉터리. md-lineage-viewer 의 가지치기 규칙과 같은 의도.
    /// 문서 축 앱도 같은 규칙으로 순회하므로 공개한다 — 두 앱이 다른 가지치기를 쓰면
    /// "안 걸린 md" 목록이 서로 달라진다.
    public static let prunedPathComponents: Set<String> = [
        ".git", ".build", "node_modules", "dist", ".worktrees", "vendor", ".venv", "Pods",
    ]
}
