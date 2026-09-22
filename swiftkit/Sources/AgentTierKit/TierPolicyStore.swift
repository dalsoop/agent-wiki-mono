import AppPathsKit
import Foundation

/// `~/.config/agent-tier/policy.json` 에 계층 정책을 영속하는 store.
///
/// 파일이 없으면 `TierPolicy.defaultPolicy` 를 그 경로에 생성해두고 돌려준다 —
/// 모든 앱이 처음 실행에도 같은 기본값을 보게 하기 위해서다.
public struct TierPolicyStore: Sendable {
    public let url: URL
    private let backing: JSONStateStore<TierPolicy>

    public init(url: URL = TierPolicyStore.defaultURL) {
        self.url = url
        self.backing = JSONStateStore(url: url)
    }

    /// `~/.config/agent-tier/policy.json`.
    public static var defaultURL: URL {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent(".config/agent-tier/policy.json", isDirectory: false)
    }

    /// 파일이 없으면 기본값을 만들어 저장한 뒤 돌려준다. 있으면 그 내용을 읽는다
    /// (디코드 실패 시에도 기본값으로 관대하게 처리).
    public func load() -> TierPolicy {
        guard FileManager.default.fileExists(atPath: url.path) else {
            let defaults = TierPolicy.defaultPolicy
            try? backing.save(defaults)
            return defaults
        }
        return backing.load(default: TierPolicy.defaultPolicy)
    }

    public func save(_ policy: TierPolicy) throws {
        try backing.save(policy)
    }

    public func resetToDefaults() throws -> TierPolicy {
        let defaults = TierPolicy.defaultPolicy
        try backing.save(defaults)
        return defaults
    }
}

extension TierPolicy {
    /// rate limit 이 감지된 계층의 모델을 fallbackModel 로 바꾼 새 정책을 돌려준다.
    /// fallback 이 없으면 원래 정책을 그대로 돌려준다(전환 없음).
    public func withFallback(for tier: AgentTier) -> TierPolicy {
        guard let current = config(for: tier), let fallback = current.fallbackModel else { return self }
        let replaced = TierConfig(
            tier: current.tier,
            model: fallback,
            effort: current.effort,
            maxConcurrent: current.maxConcurrent,
            fallbackModel: nil,
            worker: current.worker,
            fallbackWorker: current.fallbackWorker
        )
        let newConfigs = configs.map { $0.tier == tier ? replaced : $0 }
        return TierPolicy(configs: newConfigs, provider: provider)
    }
}
