import Foundation

/// I/O 항상성 컨트롤러.
///
/// 디스크 쓰기·스캔 성능 경로는 그대로 두고, **평가만** 관측된 자기 창과 비교한다.
/// 고정 SLA(50ms)나 `max(SLA, mean)` 합성은 없다.
/// 샘플이 없으면 평가하지 않는다(미관측 = 발명된 isolate 없음).
public final class HomeostaticIOController: Sendable {
    public static let shared = HomeostaticIOController()

    private let state: LockedState<[String: DomainMetric]>

    public struct DomainMetric: Sendable {
        public var totalOperations: Int = 0
        public var slowOperations: Int = 0
        public var totalDuration: TimeInterval = 0.0
        public var isIsolated: Bool = false
        public var lastEvaluatedAt: Date = Date()

        public var meanDuration: TimeInterval {
            guard totalOperations > 0 else { return 0.0 }
            return totalDuration / Double(totalOperations)
        }

        public var complaintRate: Double {
            guard totalOperations > 0 else { return 0.0 }
            return Double(slowOperations) / Double(totalOperations)
        }
    }

    public init() {
        self.state = LockedState([:])
    }

    /// 관측이 없으면 `.steady`. 발명된 기준선으로 isolate 하지 않는다.
    /// 직전 기록이 isolate 였으면 그 결정을 유지한다.
    public func evaluatePreExecution(domain: String) -> HomeostasisEngineKit.Action {
        state.withLock { metrics in
            guard let metric = metrics[domain], metric.totalOperations > 0 else {
                return .steady
            }

            if metric.isIsolated {
                return .isolateAnomaly(
                    targetName: domain,
                    reason: "Previous I/O observation isolated domain \(domain)"
                )
            }
            return .steady
        }
    }

    /// 실제 I/O 시간을 기록하고, **직전 자기 평균**과만 비교한다.
    /// 첫 샘플은 자기 자신 = 기준(항등). 느림은 `duration > priorSelf` 일 때만.
    @discardableResult
    public func recordOperation(domain: String, duration: TimeInterval) -> HomeostasisEngineKit.EquilibriumDecision {
        state.withLock { metrics in
            var metric = metrics[domain, default: DomainMetric()]
            let priorSelf: TimeInterval? = metric.totalOperations > 0 ? metric.meanDuration : nil

            metric.totalOperations += 1
            metric.totalDuration += duration
            metric.lastEvaluatedAt = Date()
            if let priorSelf, duration > priorSelf {
                metric.slowOperations += 1
            }

            let baseline = priorSelf ?? duration
            let snapshot = HomeostasisEngineKit.TimeSeriesSnapshot(
                mean: duration,
                baseline: baseline,
                complaintRate: metric.complaintRate,
                sampleCount: metric.totalOperations,
                timestamp: metric.lastEvaluatedAt
            )

            let decision = HomeostasisEngineKit.evaluateHomeostasis(
                snapshot: snapshot,
                isolateTargetName: domain
            )

            if case .isolateAnomaly = decision.action {
                metric.isIsolated = true
            } else if decision.isHealthy {
                metric.isIsolated = false
            }

            metrics[domain] = metric
            return decision
        }
    }

    public func metric(for domain: String) -> DomainMetric? {
        state.withLock { metrics in
            metrics[domain]
        }
    }

    public func reset() {
        state.withLock { metrics in
            metrics.removeAll()
        }
    }
}
