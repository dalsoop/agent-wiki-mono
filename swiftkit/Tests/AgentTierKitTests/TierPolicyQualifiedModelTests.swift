import Testing
@testable import AgentTierKit

/// `TierPolicy.qualifiedModel(for:)` 가 opencodex 프록시(kiro 프로바이더)의 실제
/// 모델 노출 규칙(`kiro/<model>` 접두사)과 맞는지 검증한다.
///
/// 2026-07-31 실측: `GET /v1/models` 로 프록시가 노출하는 실제 모델 id는
/// `kiro/claude-sonnet-5` 이지 `claude-sonnet-5` 가 아니다. 접두사 없이 codex에
/// `--model claude-sonnet-5` 를 주면 400 invalid_request_error 가 난다. 이 규칙이
/// 깨지면 3개 코디네이터의 dispatch가 전부 다시 실패한다.
@Suite("TierPolicy qualifiedModel — opencodex kiro 접두사 규칙")
struct TierPolicyQualifiedModelTests {

    @Test("kiro 프로바이더의 claude 모델은 kiro/ 접두사가 붙는다")
    func kiroClaudeModelGetsPrefixed() {
        let policy = TierPolicy(
            configs: [TierConfig(tier: .worker, model: "claude-sonnet-5", effort: "medium", maxConcurrent: 4)],
            provider: "kiro"
        )
        #expect(policy.qualifiedModel(for: .worker) == "kiro/claude-sonnet-5")
    }

    @Test("kiro 프로바이더의 gpt- 네이티브 별칭은 접두사가 붙지 않는다")
    func kiroGPTAliasStaysUnprefixed() {
        let policy = TierPolicy(
            configs: [TierConfig(tier: .worker, model: "gpt-5.6-luna", effort: "medium", maxConcurrent: 4)],
            provider: "kiro"
        )
        #expect(policy.qualifiedModel(for: .worker) == "gpt-5.6-luna")
    }

    @Test("이미 접두사가 붙어있으면 중복으로 붙이지 않는다")
    func alreadyPrefixedModelStaysAsIs() {
        let policy = TierPolicy(
            configs: [TierConfig(tier: .worker, model: "kiro/claude-sonnet-5", effort: "medium", maxConcurrent: 4)],
            provider: "kiro"
        )
        #expect(policy.qualifiedModel(for: .worker) == "kiro/claude-sonnet-5")
    }

    @Test("kiro 가 아닌 프로바이더는 접두사를 붙이지 않는다")
    func nonKiroProviderUnaffected() {
        let policy = TierPolicy(
            configs: [TierConfig(tier: .worker, model: "claude-sonnet-5", effort: "medium", maxConcurrent: 4)],
            provider: "anthropic"
        )
        #expect(policy.qualifiedModel(for: .worker) == "claude-sonnet-5")
    }

    @Test("fallback 모델도 같은 규칙으로 접두사가 붙는다")
    func fallbackModelIsQualifiedToo() {
        let policy = TierPolicy(
            configs: [TierConfig(
                tier: .worker, model: "claude-sonnet-5", effort: "medium",
                maxConcurrent: 4, fallbackModel: "claude-sonnet-4.6"
            )],
            provider: "kiro"
        )
        #expect(policy.qualifiedFallbackModel(for: .worker) == "kiro/claude-sonnet-4.6")
    }

    @Test("기본 정책(defaultPolicy)의 4계층 전부 defer(nil) 다 — 계정 기본 모델을 쓴다")
    func defaultPolicyAllTiersQualified() {
        let policy = TierPolicy.defaultPolicy
        for tier in AgentTier.allCases {
            #expect(policy.qualifiedModel(for: tier) == nil, "\(tier) 의 qualifiedModel 이 defer(nil) 가 아니다")
        }
    }

    @Test("defer(model nil) 티어는 qualifiedModel 도 nil 이다 — --model 생략 경로")
    func nilModelQualifiesToNil() {
        let policy = TierPolicy(
            configs: [TierConfig(tier: .worker, model: nil, effort: "medium", maxConcurrent: 4)],
            provider: "kiro"
        )
        #expect(policy.qualifiedModel(for: .worker) == nil)
        #expect(policy.model(for: .worker) == nil)
    }
}
