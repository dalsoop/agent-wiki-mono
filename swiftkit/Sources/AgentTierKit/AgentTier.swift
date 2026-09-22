import Foundation

/// 멀티에이전트 오케스트레이션의 계층 구분.
///
/// 계층마다 비용/성능 트레이드오프가 다르다 — meta·coordinator는 판단력이 필요해
/// 강한 모델을, worker는 구현 물량이 많아 중간 모델을, verifier는 단순 확인이라
/// 저렴한 모델을 쓰는 게 비용 최적이다.
public enum AgentTier: String, Codable, CaseIterable, Sendable {
    /// 메타 오케스트레이터 — 전체 계획, 아키텍처 판단.
    case meta
    /// 도메인 코디네이터(세미 오케스트레이터) — 도메인 판단, 태스크 분해.
    case coordinator
    /// 구현 워커 — 실제 코드 작성.
    case worker
    /// 검증 워커 — lint, 단순 체크.
    case verifier
}

/// 한 계층에 대한 모델/effort/동시성 설정.
public struct TierConfig: Codable, Equatable, Sendable {
    public let tier: AgentTier
    /// 워커에 강제할 모델. nil 이면 **defer** — `--model` 을 생략해 각 워커가
    /// 자기 계정에 설정된 기본 모델을 쓰게 한다(어느 계정/맥에서나 동작).
    public let model: String?
    /// low/medium/high/xhigh/max.
    public let effort: String
    public let maxConcurrent: Int
    /// rate limit 시 전환할 모델. 없으면 폴백하지 않는다.
    public let fallbackModel: String?
    /// 이 계층에서 쓸 워커 CLI (`codex` / `claude` / `grok` / `agy`). nil 이면 잡 스펙 기본값.
    /// AWO `tier set worker grok` 가 여기를 채운다.
    public let worker: String?
    /// 1차 워커 실패 시 전환할 fallback 워커 CLI (`grok` / `claude` 등). 없으면 잡 스펙 기본값.
    public let fallbackWorker: String?

    public init(
        tier: AgentTier,
        model: String? = nil,
        effort: String,
        maxConcurrent: Int,
        fallbackModel: String? = nil,
        worker: String? = nil,
        fallbackWorker: String? = nil
    ) {
        self.tier = tier
        self.model = model
        self.effort = effort
        self.maxConcurrent = maxConcurrent
        self.fallbackModel = fallbackModel
        self.worker = worker
        self.fallbackWorker = fallbackWorker
    }
}

/// 전체 계층 정책 — provider 하나에 대해 4계층 설정을 담는다.
public struct TierPolicy: Codable, Equatable, Sendable {
    public let configs: [TierConfig]
    /// kiro, anthropic, openai 등.
    public let provider: String

    public init(configs: [TierConfig], provider: String) {
        self.configs = configs
        self.provider = provider
    }

    /// 해당 계층의 설정. 정책에 없으면 nil.
    public func config(for tier: AgentTier) -> TierConfig? {
        configs.first { $0.tier == tier }
    }

    /// 해당 계층의 모델. nil 이면 **defer** — 워커가 자기 계정 기본 모델을 쓴다.
    /// 기본 정책의 모든 티어가 defer 다(고정 모델을 기본으로 두면 계정/맥마다 실패한다).
    public func model(for tier: AgentTier) -> String? {
        config(for: tier)?.model ?? TierPolicy.defaultPolicy.config(for: tier)?.model
    }

    /// codex `--model` 에 그대로 넘길 완전한 모델 문자열. nil 이면 defer(`--model` 생략).
    ///
    /// opencodex 프록시는 `kiro` 프로바이더의 비-네이티브 모델(claude/deepseek/glm/…)을
    /// `kiro/<model>` 접두사로만 노출한다(`GET /v1/models` 로 실측 확인, 2026-07-31).
    /// 접두사 없이 `--model claude-sonnet-5` 를 주면 codex가 기본 OpenAI 프로바이더로
    /// 보내려다 `400 invalid_request_error` 를 낸다 — 오늘 하루 반복 재현된 실패의
    /// 근본 원인이었다("opencodex sync 끊김"으로 오인했으나 실제로는 접두사 누락).
    /// `gpt-*` 모델은 OpenAI 네이티브 별칭이라 접두사를 붙이지 않는다.
    public func qualifiedModel(for tier: AgentTier) -> String? {
        Self.qualify(model(for: tier), provider: provider)
    }

    /// fallback 모델도 같은 규칙으로 접두사를 붙인다.
    public func qualifiedFallbackModel(for tier: AgentTier) -> String? {
        config(for: tier)?.fallbackModel.flatMap { Self.qualify($0, provider: provider) }
    }

    private static func qualify(_ model: String?, provider: String) -> String? {
        guard let model else { return nil }              // defer 모델은 접두사를 붙이지 않는다.
        guard provider == "kiro" else { return model }
        if model.contains("/") { return model }          // 이미 접두사가 있으면 그대로.
        if model.hasPrefix("gpt-") { return model }       // OpenAI 네이티브 별칭은 접두사 없음.
        return "kiro/\(model)"
    }
}

extension TierPolicy {
    /// 파일이 없을 때 생성하는 기본 정책. 모든 티어 모델이 nil(defer) — 워커가 각자
    /// 계정에 설정된 기본 모델을 쓰게 한다. 고정 모델을 기본으로 두면 opencodex
    /// 프록시가 없는 맥/계정에서 400 으로 실패한다(2026-08-08 실측). effort/동시성/
    /// fallback 만 티어 정책이 다스린다. 명시적 `tier set --model` 로 pin 하려면 non-nil.
    public static let defaultPolicy = TierPolicy(
        configs: [
            TierConfig(
                tier: .meta,
                model: nil,
                effort: "high",
                maxConcurrent: 1,
                fallbackModel: "claude-opus-4.8"
            ),
            TierConfig(
                tier: .coordinator,
                model: nil,
                effort: "high",
                maxConcurrent: 3,
                fallbackModel: "claude-sonnet-5"
            ),
            TierConfig(
                tier: .worker,
                model: nil,
                effort: "medium",
                maxConcurrent: 4,
                fallbackModel: "claude-sonnet-4.6"
            ),
            TierConfig(
                tier: .verifier,
                model: nil,
                effort: "low",
                maxConcurrent: 6,
                fallbackModel: "claude-sonnet-4.5"
            ),
        ],
        provider: "kiro"
    )
}
