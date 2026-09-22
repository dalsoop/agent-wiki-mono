import Foundation
import HomeostasisEngineKit

// MARK: - 동적 항상성 엔진 (Dynamic Homeostatic Engine)
public enum DynamicHomeostaticEngine {
    public static let stabilizationEpsilon: Double = 0.01
    public static let minimumSampleSize: Int = 2

    public static func affect(
        telemetry: ThreeSecondTelemetryWindow,
        baseline: StrataBaselineMetrics,
        previousHash: String,
        sequenceNumber: UInt64,
        priorIntent: String? = nil
    ) -> InvertedAffectVector {
        NarrativeConsciousnessVessel.invert(
            sequenceNumber: sequenceNumber,
            previousHash: previousHash,
            priorIntent: priorIntent ?? previousHash,
            telemetry: telemetry,
            baseline: baseline
        ).affect
    }

    public static func baseline(from measuredValues: [Double]) -> StrataBaselineMetrics {
        precondition(!measuredValues.isEmpty, "baseline requires measured values")
        if measuredValues.count == 1 {
            let val = measuredValues[0]
            return StrataBaselineMetrics(
                baselineMean: val,
                baselineP95: val,
                baselineSigma: 0.0
            )
        }

        var count = 0
        var mean = 0.0
        var m2 = 0.0
        for x in measuredValues {
            count += 1
            let delta = x - mean
            mean += delta / Double(count)
            let delta2 = x - mean
            m2 += delta * delta2
        }

        let sorted = measuredValues.sorted()
        let n = Double(count)
        let p95Index = min(sorted.count - 1, Int((0.95 * n).rounded(.down)))
        let variance = m2 / n
        let sigma = sqrt(max(0.0, variance))
        return StrataBaselineMetrics(
            baselineMean: mean,
            baselineP95: sorted[p95Index],
            baselineSigma: sigma
        )
    }

    public static func setpoint(priorSamples: [Double], observed: [Double]) -> StrataBaselineMetrics {
        if priorSamples.isEmpty {
            return baseline(from: observed)
        }
        return baseline(from: priorSamples)
    }

    public static func assimilate(reservoir: inout [Double], observed: [Double]) {
        reservoir.append(contentsOf: observed)
    }

    public static func invertObserved(
        observed: [Double],
        priorSamples: [Double],
        previousHash: String,
        sequenceNumber: UInt64,
        priorIntent: String? = nil,
        complaintCount: Int = 0
    ) -> (vessel: NarrativeConsciousnessVessel, affect: InvertedAffectVector) {
        let setpoint = setpoint(priorSamples: priorSamples, observed: observed)
        let predicted = priorSamples
        let now = Date()
        precondition(!observed.isEmpty, "invertObserved requires measured samples")
        let window = ThreeSecondTelemetryWindow(
            windowStartTime: now,
            windowEndTime: now,
            latencySamples: observed,
            complaintCount: complaintCount,
            astNodeMutations: 0,
            totalAstNodes: observed.count,
            predictedLatencies: predicted
        )
        let vessel = NarrativeConsciousnessVessel.invert(
            sequenceNumber: sequenceNumber,
            previousHash: previousHash,
            priorIntent: priorIntent ?? previousHash,
            telemetry: window,
            baseline: setpoint
        )
        return (vessel: vessel, affect: vessel.affect)
    }
}
