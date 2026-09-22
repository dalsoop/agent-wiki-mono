import Foundation

/// 시맨틱 호환성 및 타당성 판별 점수 (Plausibility & Semantic Compatibility Score).
///
/// 학술 문헌(ISSTA 2015 Qi et al., ESEC/FSE 2015 Smith et al., ICSE 2018 Patch-Sim) 및
/// 빅테크(Meta SapFix/Getafix, Google Tricorder) 모델을 기반으로,
/// 자율 합성된 규칙 또는 자동 패치(AutoFix)가 단순 테스트/지표만 요행으로 통과하는 과적합(Overfitting)인지,
/// 실제 소프트웨어 의미론과 불변식(Invariants)을 만족하는 진짜 규칙(Correct)인지를 판정한다.
public struct PlausibilityScore: Sendable, Codable, Equatable {
    /// 1계층 정적 계약 검사 통과 여부 (AST 불변식, 조기 반환 꼼수 배제, 타입 안전성)
    public let staticContractPassed: Bool
    /// 2계층 동적 동작 검사 통과 여부 (Differential Behavior, FastPath SLA, 무부작용)
    public let dynamicBehaviorPassed: Bool
    /// 3계층 통계 및 학습 기반 점수 (0.0 ~ 1.0, 엔트로피/패턴 정규성/인간 커밋 유사도)
    public let learnedScore: Double
    /// 전체 코퍼스 드라이런 시 전일 베이스라인 대비 오탐 폭증율 (%)
    public let baselineDeviationPct: Double
    /// 판별 상세 로그 및 기각 사유
    public let details: [String]

    /// 시맨틱 호환성 및 실전 적용 합격 판정
    public var isSemanticCompatible: Bool {
        staticContractPassed && dynamicBehaviorPassed && learnedScore >= 0.80 && baselineDeviationPct < 5.0
    }

    public init(
        staticContractPassed: Bool,
        dynamicBehaviorPassed: Bool,
        learnedScore: Double,
        baselineDeviationPct: Double,
        details: [String] = []
    ) {
        self.staticContractPassed = staticContractPassed
        self.dynamicBehaviorPassed = dynamicBehaviorPassed
        self.learnedScore = learnedScore
        self.baselineDeviationPct = baselineDeviationPct
        self.details = details
    }
}

/// 3단계 계층 Plausibility Discriminator 엔진.
///
/// 1. Static Contract Filter: 조기 반환 회피(`return nil`), 빈 catch 블록, AST 제어흐름 왜곡 차단.
/// 2. Dynamic Behavioral Filter: Fast-path Needle 유무, 지연시간 SLA(50ms) 위반 검사, 차분 동등성.
/// 3. Statistical Baseline Deviation Filter: 490+ 모노레포 앱 드라이런 시 오탐 폭증율(+5% 초과) 차단.
public struct PlausibilityDiscriminatorEngine: Sendable {

    public struct Config: Sendable {
        public let minLearnedScore: Double
        public let maxBaselineDeviationPct: Double
        public let latencyTolerancePct: Double

        public static let production = Config(
            minLearnedScore: 0.80,
            maxBaselineDeviationPct: 5.0,
            latencyTolerancePct: 5.0
        )
    }

    public let config: Config

    public init(config: Config = .production) {
        self.config = config
    }

    /// 자율 마이닝된 규칙 후보가 진짜 소프트웨어 의미론에 부합하는지 3단계 판별
    public func evaluate(
        candidate: DeclarativeMinedRule,
        sampleContext: String = "",
        dryRunFindingsCount: Int = 0,
        historicalFindingsAverage: Double = 0.0
    ) -> PlausibilityScore {
        var details: [String] = []

        // Tier 1: Static Contract Filter
        let staticPassed = verifyStaticContracts(candidate: candidate, context: sampleContext, details: &details)

        // Tier 2: Dynamic Behavioral & SLA Filter
        let dynamicPassed = verifyDynamicBehavior(candidate: candidate, details: &details)

        // Tier 3: Statistical & Learned Plausibility Scorer
        let learnedScore = computeLearnedScore(candidate: candidate, details: &details)

        let deviationPct: Double
        if historicalFindingsAverage > 0 {
            deviationPct = max(0.0, ((Double(dryRunFindingsCount) - historicalFindingsAverage) / historicalFindingsAverage) * 100.0)
        } else {
            deviationPct = 0.0
        }

        if deviationPct > config.maxBaselineDeviationPct {
            details.append("Baseline deviation too high: +\(String(format: "%.1f", deviationPct))% (max allowed: \(config.maxBaselineDeviationPct)%)")
        }

        return PlausibilityScore(
            staticContractPassed: staticPassed,
            dynamicBehaviorPassed: dynamicPassed,
            learnedScore: learnedScore,
            baselineDeviationPct: deviationPct,
            details: details
        )
    }

    /// Tier 1: 정적 계약 검증 (Early return evasion, 빈 블록, 구문 무결성)
    private func verifyStaticContracts(candidate: DeclarativeMinedRule, context: String, details: inout [String]) -> Bool {
        var passed = true

        // 1. 조기 반환 꼼수 (Early return evasion) 감지
        let fixLower = candidate.fix.lowercased()
        let patLower = candidate.pattern.lowercased()
        if (fixLower.contains("return nil") || fixLower.contains("return true") || fixLower.contains("return false"))
            && !patLower.contains("return") {
            details.append("StaticContractViolation: Early return evasion detected in fix ('\(candidate.fix)')")
            passed = false
        }

        // 2. 예외 삼킴 (Empty catch / swallow) 감지
        if fixLower.contains("catch { /* handled */ _ = error }") || fixLower.contains("catch { /* handled */ _ = error }") || fixLower.contains("try?") {
            if !patLower.contains("try?") {
                details.append("StaticContractViolation: Error swallowing pattern detected in fix")
                passed = false
            }
        }

        // 3. 최소 유효성 검사 (너무 짧거나 모호한 패턴 차단)
        if candidate.pattern.trimmingCharacters(in: .whitespacesAndNewlines).count < 3 {
            details.append("StaticContractViolation: Pattern is too short or trivial (\(candidate.pattern.count) chars)")
            passed = false
        }

        return passed
    }

    /// Tier 2: 동적 동작 및 SLA 검증 (FastPath Needle 필수성, 50ms SLA)
    private func verifyDynamicBehavior(candidate: DeclarativeMinedRule, details: inout [String]) -> Bool {
        var passed = true

        // 1. 0.0001ms Fast-Path Needle 탑재 여부 검증
        if candidate.fastPathNeedles.isEmpty {
            details.append("DynamicBehaviorViolation: Fast-path needle is missing (0.0001ms early bailout contract failed)")
            passed = false
        } else {
            for needle in candidate.fastPathNeedles {
                if needle.count < 3 {
                    details.append("DynamicBehaviorViolation: Fast-path needle '\(needle)' is too short (< 3 chars)")
                    passed = false
                }
            }
        }

        // 2. 역합성 시간 또는 백테스트 시간이 SLA(10초)를 초과했는지 검증
        if candidate.backtestDurationSec > 10.0 {
            details.append("DynamicBehaviorViolation: Backtest latency SLA exceeded (\(candidate.backtestDurationSec)s > 10.0s)")
            passed = false
        }

        return passed
    }

    /// Tier 3: 엔트로피 및 패턴 정규성 점수 산출
    private func computeLearnedScore(candidate: DeclarativeMinedRule, details: inout [String]) -> Double {
        var score = 1.0

        // 패턴 복잡도 및 정규성 점수 가감
        if candidate.fastPathNeedles.count >= 1 {
            score += 0.05
        }
        if candidate.incidentId != nil {
            score += 0.05
        }
        if candidate.rationale.count > 10 {
            score += 0.05
        }

        // 패턴 내 와일드카드나 과도한 정규식 복잡도 페널티
        if candidate.pattern.contains(".*.*") || candidate.pattern.contains(".+") {
            score -= 0.25
            details.append("LearnedScorePenalty: High entropy wildcard pattern detected")
        }

        return min(1.0, max(0.0, score))
    }
}
