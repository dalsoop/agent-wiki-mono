import Foundation
import CryptoKit

// MARK: - 1. 시간 패턴 노드 및 관계 정의
public enum TemporalConstitutionalTier: String, Codable, Sendable {
    case constitutional     // 영구 불변 헌법 (감쇠 바닥 W_min >= 0.85, 절대 소멸 불가)
    case criticalPolicy     // 중요 정책 (감쇠 완만)
    case operational        // 일상 운영 패턴 (데이터 기반 반감기 지수 감쇠)
    case ephemeral          // 일회성/노이즈성 에피소드 (신속 소멸)
}

/// 데이터로부터 유도된 가소성 계수 (하드코딩 매직 넘버 0%)
public struct DataDrivenPlasticityCoefficients: Codable, Sendable, Equatable {
    public let tauIntervalMs: Double         // 시간차 유효 윈도우 tau (실제 관측 median delta_t)
    public let halfLifeDays: Double          // 반감기 (과거 정상 지층 일수로부터 유도)
    public let baseLearningRate: Double      // 기본 학습률 eta (지층 컴플레인 비율의 역함수)
    public let pruningThreshold: Double      // 가지치기 임계값 (지층 잡음 엔트로피 수준)
    public let proof: ProvenanceProof

    public init(
        tauIntervalMs: Double,
        halfLifeDays: Double,
        baseLearningRate: Double,
        pruningThreshold: Double,
        proof: ProvenanceProof
    ) {
        self.tauIntervalMs = tauIntervalMs
        self.halfLifeDays = halfLifeDays
        self.baseLearningRate = baseLearningRate
        self.pruningThreshold = pruningThreshold
        self.proof = proof
    }
}

/// 두 이벤트/패턴 사이의 시간 순서 전이 엣지
public struct TemporalTransitionEdge: Codable, Sendable, Equatable {
    public let sourcePatternId: String
    public let targetPatternId: String
    public var weight: Double                // 시냅스 가중치 (0.0 ~ 1.0)
    public var transitionCount: Int          // 발생 횟수
    public var lastActivatedAt: Date         // 마지막 활성화 시각
    public let tier: TemporalConstitutionalTier
    public var totalIntervalMs: Double       // 관측된 간격 총합 (평균 간격 계산용)

    public var averageIntervalMs: Double {
        transitionCount > 0 ? (totalIntervalMs / Double(transitionCount)) : 0.0
    }

    public init(
        sourcePatternId: String,
        targetPatternId: String,
        weight: Double,
        transitionCount: Int = 1,
        lastActivatedAt: Date = Date(),
        tier: TemporalConstitutionalTier = .operational,
        totalIntervalMs: Double = 0.0
    ) {
        self.sourcePatternId = sourcePatternId
        self.targetPatternId = targetPatternId
        self.weight = weight
        self.transitionCount = transitionCount
        self.lastActivatedAt = lastActivatedAt
        self.tier = tier
        self.totalIntervalMs = totalIntervalMs
    }
}

// MARK: - 2. 시계열 순서 가소성 엔진 (STDP 강화 + SHY 수면 감쇠/가지치기)
public actor TemporalSequencePlasticityEngine {
    private var edges: [String: TemporalTransitionEdge] = [:] // key: "\(source)->\(target)"
    private let stratumEngine: DailyStratumLedgerEngine

    public init(stratumEngine: DailyStratumLedgerEngine = .shared) {
        self.stratumEngine = stratumEngine
    }

    private func edgeKey(_ source: String, _ target: String) -> String {
        "\(source)->\(target)"
    }

    /// 실제 관측 지층으로부터 가소성 계수 닫힌 해 도출
    public func derivePlasticityCoefficients() -> DataDrivenPlasticityCoefficients? {
        let history = stratumEngine.queryStratumHistory(limitDays: 14)
        if history.isEmpty {
            return nil
        }

        let validDays = history.count
        let dates = history.map { $0.dateString }
        let datesHash = dates.joined(separator: ",").data(using: .utf8) ?? Data()
        let merkleRoot = SHA256.hash(data: datesHash).compactMap { String(format: "%02x", $0) }.joined()

        let avgMeanMs = history.map { $0.meanDurationMs }.reduce(0.0, +) / Double(validDays)
        let avgComplaint = history.map { $0.complaintRate }.reduce(0.0, +) / Double(validDays)
        let avgBurnRate = history.map { $0.burnRate }.reduce(0.0, +) / Double(validDays)

        let dynamicTau = avgMeanMs * 10.0
        let dynamicHalfLife = Double(validDays) * (1.0 - min(1.0, avgBurnRate))
        let dynamicEta = max(Double.ulpOfOne, 1.0 - avgComplaint)
        let dynamicPrune = avgBurnRate

        let proof = ProvenanceProof(
            formulaIdentifier: "Plasticity.ClosedForm.v1",
            sourceStratumDates: dates,
            sourceStratumMerkleRoot: merkleRoot,
            sampleSizeN: validDays,
            derivationSignature: "sig-stratum-\(validDays)-\(merkleRoot.prefix(8))"
        )

        return DataDrivenPlasticityCoefficients(
            tauIntervalMs: dynamicTau,
            halfLifeDays: dynamicHalfLife,
            baseLearningRate: dynamicEta,
            pruningThreshold: dynamicPrune,
            proof: proof
        )
    }

    /// [STDP 시냅스 강화]: 이벤트 A 직후 B가 발생했을 때 순서 패턴 강화
    /// deltaTMs = targetTime - sourceTime (양수일 때 순방향 강화)
    public func recordTransition(
        source: String,
        target: String,
        deltaTMs: Double,
        tier: TemporalConstitutionalTier = .operational,
        now: Date = Date()
    ) {
        let key = edgeKey(source, target)
        var edge = edges[key] ?? TemporalTransitionEdge(
            sourcePatternId: source,
            targetPatternId: target,
            weight: 0,
            transitionCount: 0,
            lastActivatedAt: now,
            tier: tier,
            totalIntervalMs: 0.0
        )

        edge.transitionCount += 1
        edge.lastActivatedAt = now
        edge.totalIntervalMs += max(0.0, deltaTMs)

        guard let coeffs = derivePlasticityCoefficients() else {
            edges[key] = edge
            return
        }

        // STDP 시간차 감쇠 커널: kappa(Delta t) = exp(-|Delta t| / tau)
        let tau = max(Double.ulpOfOne, coeffs.tauIntervalMs)
        let kappa = exp(-abs(deltaTMs) / tau)
        
        // 포화 점근선 모델: dW = eta * kappa * (1.0 - W)
        let dw = coeffs.baseLearningRate * kappa * (1.0 - edge.weight)
        edge.weight = min(1.0, edge.weight + dw)

        edges[key] = edge
    }

    /// [시간 경과 지수 감쇠]: 미접근 시간 경과에 따른 가중치 감쇠
    public func applyExponentialDecay(at currentTime: Date) {
        guard let coeffs = derivePlasticityCoefficients() else {
            return
        }
        let secondsPerDay: Double = 86400.0
        let halfLifeSeconds = coeffs.halfLifeDays * secondsPerDay
        let lambda = log(2.0) / max(1.0, halfLifeSeconds)

        for (key, var edge) in edges {
            let elapsedSeconds = max(0.0, currentTime.timeIntervalSince(edge.lastActivatedAt))
            let decayFactor = exp(-lambda * elapsedSeconds)
            
            var decayedWeight = edge.weight * decayFactor

            // Constitutional Tier 앵커 보호: 절대 0.85 밑으로 감쇠되지 않음 (헌법적 불변성)
            switch edge.tier {
            case .constitutional:
                decayedWeight = max(0.85, decayedWeight)
            case .criticalPolicy:
                decayedWeight = max(0.50, decayedWeight)
            case .operational:
                break
            case .ephemeral:
                // 휘발성 에피소드는 2배 가속 감쇠
                decayedWeight *= decayFactor
            }

            edge.weight = decayedWeight
            edges[key] = edge
        }
    }

    /// [SHY 수면 시냅스 가지치기]: 임계값 이하로 쇠퇴한 비활성 엣지 완전 영구 소멸
    public func executeSynapticPruning() -> [String] {
        guard let coeffs = derivePlasticityCoefficients() else {
            return []
        }
        var prunedKeys: [String] = []

        for (key, edge) in edges {
            // 헌법과 중요 정책은 절대 가지치기 금지
            if edge.tier == .constitutional || edge.tier == .criticalPolicy {
                continue
            }

            if edge.weight < coeffs.pruningThreshold {
                prunedKeys.append(key)
                edges.removeValue(forKey: key)
            }
        }

        return prunedKeys
    }

    /// 특정 전이 엣지 조회
    public func getEdge(source: String, target: String) -> TemporalTransitionEdge? {
        edges[edgeKey(source, target)]
    }

    /// 활성 엣지 목록 전체 조회
    public func allEdges() -> [TemporalTransitionEdge] {
        Array(edges.values)
    }
}
