import Foundation

/// 인지신경과학의 예측 부호화(Predictive Coding) 및 3초 시간 통합 윈도우(Temporal Integration Window) 기반
/// 예측 부호화 서프라이즈 루프 인터페이스
public struct PredictiveSurpriseLoop: Sendable {

    /// 1단계: 항상성 데이터로부터 선제 산출된 하향식 사전 가설 (Top-down Generative Prior)
    public struct GenerativePriorSnapshot: Codable, Sendable, Equatable {
        public let timestamp: Date
        public let baselineSampleSize: Int
        public let expectedClusterPurityRate: Double   // 기대 군집화 순도 (1.0 = 100% 군집화)
        public let maxAcceptableOrphanRate: Double     // 최대 허용 고아(미분류)율 (0.0 = 무관용)
        public let precisionWeight: Double             // 오차 정밀도 가중치 (Precision weighting)
        public let isLocked: Bool                      // 0초 시점에 항상성 베이스라인 락 여부

        public init(
            timestamp: Date = Date(),
            baselineSampleSize: Int,
            expectedClusterPurityRate: Double,
            maxAcceptableOrphanRate: Double,
            precisionWeight: Double,
            isLocked: Bool
        ) {
            self.timestamp = timestamp
            self.baselineSampleSize = baselineSampleSize
            self.expectedClusterPurityRate = expectedClusterPurityRate
            self.maxAcceptableOrphanRate = maxAcceptableOrphanRate
            self.precisionWeight = precisionWeight
            self.isLocked = isLocked
        }
    }

    /// 2단계: 3초 시간 통합 윈도우 후 관측된 실제 데이터 샘플 (Delayed Execution Observation)
    public struct DelayedExecutionSample: Sendable, Equatable {
        public let elapsedSeconds: Double
        public let totalRegisteredRules: Int
        public let declaredClusterRules: Int
        public let excludedRules: Int
        public let unclassifiedOrphanRules: [String]
        public let observedClusterPurityRate: Double

        public init(
            elapsedSeconds: Double,
            totalRegisteredRules: Int,
            declaredClusterRules: Int,
            excludedRules: Int,
            unclassifiedOrphanRules: [String]
        ) {
            self.elapsedSeconds = elapsedSeconds
            self.totalRegisteredRules = totalRegisteredRules
            self.declaredClusterRules = declaredClusterRules
            self.excludedRules = excludedRules
            self.unclassifiedOrphanRules = unclassifiedOrphanRules
            if totalRegisteredRules > 0 {
                self.observedClusterPurityRate = Double(declaredClusterRules + excludedRules) / Double(totalRegisteredRules)
            } else {
                self.observedClusterPurityRate = 0.0
            }
        }
    }

    /// 3단계: 사전 가설과 실데이터 간의 예측 오차 및 자유 에너지 판정 (Prediction Error Delta)
    public struct PredictionErrorDelta: Sendable, Equatable {
        public let priorPurityRate: Double
        public let observedPurityRate: Double
        public let residualError: Double             // 잔차 (Residual Error ε = Expected - Observed)
        public let freeEnergySurprise: Double         // 변분 자유 에너지 서프라이즈 (Precision * ε^2)
        public let isTolerable: Bool                  // 시스템 항상성 유지 가능 여부
        public let orphanViolationIDs: [String]
        public let diagnosticMessage: String

        public init(
            priorPurityRate: Double,
            observedPurityRate: Double,
            residualError: Double,
            freeEnergySurprise: Double,
            isTolerable: Bool,
            orphanViolationIDs: [String],
            diagnosticMessage: String
        ) {
            self.priorPurityRate = priorPurityRate
            self.observedPurityRate = observedPurityRate
            self.residualError = residualError
            self.freeEnergySurprise = freeEnergySurprise
            self.isTolerable = isTolerable
            self.orphanViolationIDs = orphanViolationIDs
            self.diagnosticMessage = diagnosticMessage
        }
    }

    public init() {}

    /// T = 0s: 사전 가설 스냅샷 선제 가계산
    public func precomputeGenerativePrior(sampleCount: Int = 1) -> GenerativePriorSnapshot {
        GenerativePriorSnapshot(
            timestamp: Date(),
            baselineSampleSize: max(sampleCount, 1),
            expectedClusterPurityRate: 1.0,
            maxAcceptableOrphanRate: 0.0,
            precisionWeight: 10.0,
            isLocked: true
        )
    }

    /// T = +3s: 3초 시간 통합 윈도우 관측 데이터 수신
    public func observeExecutionSample(
        totalRules: Int = 0,
        declaredClusterRules: Int = 0,
        excludedRules: Int = 0,
        orphans: [String] = [],
        simulatedWindowSeconds: Double = 3.0
    ) -> DelayedExecutionSample {
        DelayedExecutionSample(
            elapsedSeconds: simulatedWindowSeconds,
            totalRegisteredRules: totalRules,
            declaredClusterRules: declaredClusterRules,
            excludedRules: excludedRules,
            unclassifiedOrphanRules: orphans
        )
    }

    /// T = +3s: 예측 오차 산출 및 항상성 판정
    public func evaluatePredictionError(
        prior: GenerativePriorSnapshot,
        observation: DelayedExecutionSample
    ) -> PredictionErrorDelta {
        let residual = max(0.0, prior.expectedClusterPurityRate - observation.observedClusterPurityRate)
        let freeEnergy = prior.precisionWeight * (residual * residual)
        let isTolerable = (residual <= prior.maxAcceptableOrphanRate) && observation.unclassifiedOrphanRules.isEmpty

        let diagnostic: String
        if isTolerable {
            diagnostic = "항상성 평형 유지: 잔차 오차 \(String(format: "%.4f", residual)), 자유 에너지 \(String(format: "%.4f", freeEnergy))로 안정 상태입니다."
        } else {
            diagnostic = "변분 자유 에너지 폭증(Surprise): \(observation.unclassifiedOrphanRules.count)건의 규칙이 군집화되지 않고 .unclassified로 남아 잔차 오차 \(String(format: "%.4f", residual)) 발생."
        }

        return PredictionErrorDelta(
            priorPurityRate: prior.expectedClusterPurityRate,
            observedPurityRate: observation.observedClusterPurityRate,
            residualError: residual,
            freeEnergySurprise: freeEnergy,
            isTolerable: isTolerable,
            orphanViolationIDs: observation.unclassifiedOrphanRules,
            diagnosticMessage: diagnostic
        )
    }
}
