import Testing
@testable import RuleMiningKit

@Suite("NarrativeInversionFormulaTests - 분모 붕괴 차단 및 정동 역산 불변식 검증")
struct NarrativeInversionFormulaTests {

    // MARK: - Test 1. 분모 붕괴 방지(No Infinity/NaN)
    // baselineSigma가 0.0 또는 1e-16 수준으로 극소일 때도
    // naturalFloor = max(0.01, abs(predMean) * 0.01)와
    // effectiveSigma = max(baselineSigma, naturalFloor)에 의해
    // 항상성 델타(ΔH)가 발산(예: 5.84e23)하지 않고 정상 범위(0.0 <= ΔH <= 100.0)로 완벽 수렴함을 검증.
    @Test("Test 1. 분모 붕괴 방지(No Infinity/NaN): baselineSigma 극소(0.0 및 1e-16) 시 ΔH 정상 수렴 검증")
    func testZeroAndNearZeroSigmaDoesNotDiverge() {
        let testSigmas: [Double] = [0.0, 1e-16, 1e-20, Double.ulpOfOne]
        let observedLatencies = [10.0, 10.5, 9.8]
        let predictedLatencies = [10.0, 10.0, 10.0]

        for sigma in testSigmas {
            // Direct closedSurprise invocation
            let result = NarrativeConsciousnessVessel.closedSurprise(
                observed: observedLatencies,
                predicted: predictedLatencies,
                baselineSigma: sigma,
                astDensity: 0.02
            )

            switch result {
            case .opened:
                Issue.record("Expected closed homeostasis for non-empty observed and predicted")
            case .closed(let deltaH):
                #expect(!deltaH.isNaN, "Delta H must not be NaN for sigma=\(sigma)")
                #expect(!deltaH.isInfinite, "Delta H must not be Infinite for sigma=\(sigma)")
                #expect(deltaH >= 0.0 && deltaH <= 100.0, "Delta H (\(deltaH)) must converge within [0.0, 100.0] for sigma=\(sigma)")
            }

            // End-to-end invert() verification
            let window = ThreeSecondTelemetryWindow(
                latencySamples: observedLatencies,
                complaintCount: 0,
                astNodeMutations: 2,
                totalAstNodes: 100,
                predictedLatencies: predictedLatencies
            )
            let baseline = StrataBaselineMetrics(
                baselineMean: 10.0,
                baselineP95: 11.0,
                baselineSigma: sigma
            )
            let vessel = NarrativeConsciousnessVessel.invert(
                sequenceNumber: 1,
                previousHash: "genesis",
                priorIntent: "Verify no denominator collapse",
                telemetry: window,
                baseline: baseline
            )

            let delta = vessel.affect.homeostaticDelta
            #expect(!delta.isNaN, "Vessel affect delta must not be NaN")
            #expect(!delta.isInfinite, "Vessel affect delta must not be Infinite")
            #expect(delta >= 0.0 && delta <= 100.0, "Vessel affect delta (\(delta)) must converge within [0.0, 100.0]")
        }
    }

    // MARK: - Test 2. 지터(Jitter) 충격 복원력
    // 0.17ms 미세 지터 유입 시 분모 붕괴 없이 유한한 수치로 닫히는지 검증.
    @Test("Test 2. 지터(Jitter) 충격 복원력: 0.17ms 미세 지터 유입 시 유한한 수치로 안정적으로 닫힘 검증")
    func testMicroJitterResilience() {
        let baselineMean = 5.0
        let jitter = 0.17 // ms
        let observed = [baselineMean + jitter, baselineMean - jitter, baselineMean + (jitter * 0.5)]
        let predicted = [baselineMean, baselineMean, baselineMean]

        // baselineSigma가 0인 극한 상황에서도 0.17ms 지터가 자연스럽게 흡수되는지 확인
        let result = NarrativeConsciousnessVessel.closedSurprise(
            observed: observed,
            predicted: predicted,
            baselineSigma: 0.0,
            astDensity: 0.0
        )

        switch result {
        case .opened:
            Issue.record("Expected closed homeostasis for micro-jitter input")
        case .closed(let deltaH):
            #expect(!deltaH.isNaN, "Delta H must not be NaN under 0.17ms jitter")
            #expect(!deltaH.isInfinite, "Delta H must not be Infinite under 0.17ms jitter")
            #expect(deltaH >= 0.0 && deltaH <= 100.0, "Delta H (\(deltaH)) must stay within normal range under 0.17ms jitter")
            // predMean = 5.0 -> naturalFloor = max(0.01, 0.05) = 0.05
            // effectiveSigma = max(0.0, 0.05) = 0.05
            // error ~ 0.17 / 0.05 = 3.4 -> error^2 ~ 11.56
            // deltaH should be around 8~12, well within finite range
            #expect(deltaH < 20.0, "Delta H should be proportionally bounded by naturalFloor")
        }
    }

    // MARK: - Test 3. 관측치 0개 및 예측치 부재 시 Opened 상태 검증
    // 빈 관측이나 빈 예측 시 무리하게 평균으로 때우지 않고 명확히 .opened를 반환하는지 검증.
    @Test("Test 3. 관측치 0개 및 예측치 부재 시 Opened 상태 검증: 빈 예측 또는 빈 관측 시 .opened 반환")
    func testOpenedStateOnEmptyObservationOrPrediction() {
        // Case A: 빈 예측 (predicted is empty)
        let emptyPredResult = NarrativeConsciousnessVessel.closedSurprise(
            observed: [10.0, 12.0],
            predicted: [],
            baselineSigma: 1.0,
            astDensity: 0.0
        )
        #expect(emptyPredResult == .opened, "Empty predicted samples must yield .opened state")

        // Case B: 빈 관측 (observed is empty)
        let emptyObsResult = NarrativeConsciousnessVessel.closedSurprise(
            observed: [],
            predicted: [10.0, 12.0],
            baselineSigma: 1.0,
            astDensity: 0.0
        )
        #expect(emptyObsResult == .opened, "Empty observed samples must yield .opened state")

        // Case C: 둘 다 빈 경우
        let bothEmptyResult = NarrativeConsciousnessVessel.closedSurprise(
            observed: [],
            predicted: [],
            baselineSigma: 1.0,
            astDensity: 0.0
        )
        #expect(bothEmptyResult == .opened, "Both empty must yield .opened state")

        // Case D: Invert E2E 시 predictedLatencies 부재 시 homeostasis가 .opened 상태인지 확인
        let windowWithoutPred = ThreeSecondTelemetryWindow(
            latencySamples: [10.0, 11.0],
            complaintCount: 0,
            astNodeMutations: 0,
            totalAstNodes: 10,
            predictedLatencies: []
        )
        let baseline = StrataBaselineMetrics(
            baselineMean: 10.0,
            baselineP95: 12.0,
            baselineSigma: 1.0
        )
        let vessel = NarrativeConsciousnessVessel.invert(
            sequenceNumber: 2,
            previousHash: "hash-opened",
            priorIntent: "Verify opened state",
            telemetry: windowWithoutPred,
            baseline: baseline
        )
        #expect(vessel.affect.homeostasis == .opened, "Affect homeostasis must be .opened when predictedLatencies is empty")
        #expect(vessel.narrativeSummary.contains("예측 표본이 없어 창이 열렸다"), "Narrative must reflect opened window")
    }
}
