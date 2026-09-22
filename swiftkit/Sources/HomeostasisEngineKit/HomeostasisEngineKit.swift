import Foundation

/// 공통 항상성 엔진 킷 (Homeostasis Engine Kit)
///
/// 시간 축(시계열) 기반으로 정상 상태 대비 편차(SLA 지연, 에러율, 컴플레인)를 감지하고
/// 자율 제어(격리, 서킷 브레이커, 자율 치유) 결정을 산출한다.
public enum HomeostasisEngineKit: Sendable {

    /// 항상성 조치 결정
    public enum Action: Sendable, Equatable {
        case steady
        case throttle(rate: Double)
        case isolateAnomaly(targetName: String, reason: String)
        case selfHeal
    }

    /// 항상성 종합 판정 결과
    public struct EquilibriumDecision: Sendable, Equatable {
        public let isHealthy: Bool
        public let action: Action
        public let burnRate: Double

        public init(isHealthy: Bool, action: Action, burnRate: Double) {
            self.isHealthy = isHealthy
            self.action = action
            self.burnRate = burnRate
        }
    }

    /// 시계열 스냅샷
    public struct TimeSeriesSnapshot: Sendable, Equatable {
        public let mean: Double
        public let baseline: Double
        public let complaintRate: Double
        public let sampleCount: Int
        public let timestamp: Date

        public init(
            mean: Double,
            baseline: Double,
            complaintRate: Double,
            sampleCount: Int,
            timestamp: Date = Date()
        ) {
            self.mean = mean
            self.baseline = baseline
            self.complaintRate = complaintRate
            self.sampleCount = sampleCount
            self.timestamp = timestamp
        }
    }

    /// 항상성 평가 함수
    public static func evaluateHomeostasis(
        snapshot: TimeSeriesSnapshot,
        sensitivity: Double = 1.20,
        complaintThreshold: Double = 0.03,
        isolateTargetName: String = "Anomaly"
    ) -> EquilibriumDecision {
        let burnRate: Double
        if snapshot.baseline > 0 {
            burnRate = (snapshot.mean - snapshot.baseline) / snapshot.baseline
        } else {
            burnRate = 0.0
        }

        // 1. 컴플레인 비율 임계치 초과 검사
        if snapshot.complaintRate >= complaintThreshold {
            return EquilibriumDecision(
                isHealthy: false,
                action: .isolateAnomaly(
                    targetName: isolateTargetName,
                    reason: "Complaint rate \(String(format: "%.2f", snapshot.complaintRate * 100))% exceeded threshold \(String(format: "%.2f", complaintThreshold * 100))%"
                ),
                burnRate: burnRate
            )
        }

        // 2. 기준선 대비 민감도(기본 +20%) 초과 지연 검사 또는 0 기준선 절대 폭주 검사
        let isPositiveBaselineExceeded = snapshot.baseline > 0 && snapshot.mean >= snapshot.baseline * sensitivity
        let isNonPositiveBaselineRunaway = snapshot.baseline <= 0 && snapshot.mean > 1000.0
        if isPositiveBaselineExceeded || isNonPositiveBaselineRunaway {
            let effectiveBurnRate = snapshot.baseline > 0 ? burnRate : (snapshot.mean / 1000.0)
            return EquilibriumDecision(
                isHealthy: false,
                action: .isolateAnomaly(
                    targetName: isolateTargetName,
                    reason: snapshot.baseline > 0
                        ? "Mean latency \(String(format: "%.3f", snapshot.mean)) exceeded baseline \(String(format: "%.3f", snapshot.baseline)) by +\(String(format: "%.1f", burnRate * 100))%"
                        : "Mean latency \(String(format: "%.3f", snapshot.mean)) runaway on non-positive baseline"
                ),
                burnRate: effectiveBurnRate
            )
        }

        // 3. 정상 상태
        return EquilibriumDecision(
            isHealthy: true,
            action: .steady,
            burnRate: max(0.0, burnRate)
        )
    }
}
