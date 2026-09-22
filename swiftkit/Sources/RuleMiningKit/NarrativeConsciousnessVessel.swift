import Foundation
import CryptoKit

// MARK: - 1. 3초 물리 텔레메트리 관측 윈도우 (No Hardcoding)
public struct ThreeSecondTelemetryWindow: Sendable, Codable, Equatable {
    public let windowStartTime: Date
    public let windowEndTime: Date
    public let latencySamples: [Double]        // 3초간 실측된 개별 처리 지연시간(ms)
    public let complaintCount: Int             // 3초간 발생한 컴플레인/에러 건수
    public let astNodeMutations: Int           // 3초간 변형된 AST 노드 수
    public let totalAstNodes: Int              // 전체 AST 노드 수
    public let predictedLatencies: [Double]    // 3초 전 Prior 가계산 예측치

    public init(
        windowStartTime: Date = Date(),
        windowEndTime: Date = Date(),
        latencySamples: [Double],
        complaintCount: Int = 0,
        astNodeMutations: Int = 0,
        totalAstNodes: Int = 0,
        predictedLatencies: [Double] = []
    ) {
        self.windowStartTime = windowStartTime
        self.windowEndTime = windowEndTime
        self.latencySamples = latencySamples
        self.complaintCount = complaintCount
        self.astNodeMutations = astNodeMutations
        self.totalAstNodes = totalAstNodes > 0 ? totalAstNodes : max(1, latencySamples.count)
        self.predictedLatencies = predictedLatencies
    }
}

// MARK: - 2. 지층 롤링 베이스라인 통계량
public struct StrataBaselineMetrics: Sendable, Codable, Equatable {
    public let baselineMean: Double
    public let baselineP95: Double
    public let baselineSigma: Double

    public init(baselineMean: Double, baselineP95: Double, baselineSigma: Double) {
        self.baselineMean = baselineMean
        self.baselineP95 = baselineP95
        self.baselineSigma = baselineSigma
    }
}

public enum InvertedHomeostasis: Sendable, Codable, Equatable, Hashable {
    case opened
    case closed(delta: Double)
}

// MARK: - 3. 데이터 기반 역산 정동 벡터 (Inverted Affect Vector)
public struct InvertedAffectVector: Sendable, Codable, Equatable {
    public let valence: Double
    public let arousal: Double
    public let homeostasis: InvertedHomeostasis

    public init(valence: Double, arousal: Double, homeostaticDelta: Double) {
        self.valence = valence
        self.arousal = arousal
        self.homeostasis = .closed(delta: homeostaticDelta)
    }

    public init(valence: Double, arousal: Double, homeostasis: InvertedHomeostasis) {
        self.valence = valence
        self.arousal = arousal
        self.homeostasis = homeostasis
    }

    public var homeostaticDelta: Double {
        switch homeostasis {
        case .closed(let delta):
            return delta
        case .opened:
            preconditionFailure("homeostaticDelta exists only after predicted latencies close the window")
        }
    }
}

// MARK: - 4. Tier-0 3초 서사 의식 원장 그릇 (Narrative Consciousness Vessel)
public struct NarrativeConsciousnessVessel: Sendable, Codable, Equatable {
    public let sequenceNumber: UInt64
    public let epochTimestamp: Date
    public let priorIntent: String
    public let telemetrySnapshot: ThreeSecondTelemetryWindow
    public let baselineMetrics: StrataBaselineMetrics
    public let affect: InvertedAffectVector
    public let narrativeSummary: String
    public let proof: ProvenanceProof

    public init(
        sequenceNumber: UInt64,
        epochTimestamp: Date,
        priorIntent: String,
        telemetrySnapshot: ThreeSecondTelemetryWindow,
        baselineMetrics: StrataBaselineMetrics,
        affect: InvertedAffectVector,
        narrativeSummary: String,
        proof: ProvenanceProof
    ) {
        self.sequenceNumber = sequenceNumber
        self.epochTimestamp = epochTimestamp
        self.priorIntent = priorIntent
        self.telemetrySnapshot = telemetrySnapshot
        self.baselineMetrics = baselineMetrics
        self.affect = affect
        self.narrativeSummary = narrativeSummary
        self.proof = proof
    }

    private struct InversionIntermediate: Sendable {
        let affect: InvertedAffectVector
        let mu3s: Double
        let clampedValence: Double
        let arousal: Double
    }

    private static func deriveAffect(
        telemetry: ThreeSecondTelemetryWindow,
        baseline: StrataBaselineMetrics
    ) -> InversionIntermediate {
        let sampleCount = Double(telemetry.latencySamples.count)
        let mu3s = telemetry.latencySamples.reduce(0.0, +) / sampleCount

        let variance3s = telemetry.latencySamples.map { pow($0 - mu3s, 2) }.reduce(0.0, +) / sampleCount
        let sigma3s = sqrt(variance3s)

        let complaintRate = Double(telemetry.complaintCount) / sampleCount
        let astSum = telemetry.astNodeMutations + telemetry.totalAstNodes
        let astDensity: Double
        if telemetry.totalAstNodes > 0 && astSum > 0 && telemetry.astNodeMutations >= 0 {
            astDensity = Double(telemetry.astNodeMutations) / Double(astSum)
        } else {
            astDensity = 0.0
        }

        // a) Valence 닫힌 해 역산: (기준치 - 실측치) / max(기준치, 실측치)
        let rawValence: Double
        if baseline.baselineMean < 0 || mu3s < 0 {
            let denom = max(abs(baseline.baselineMean), abs(mu3s))
            let diff = abs(baseline.baselineMean) - abs(mu3s)
            rawValence = denom > 0 ? diff / denom : 0.0
        } else {
            let maxDenominator = max(baseline.baselineMean, mu3s)
            rawValence = maxDenominator > 0 ? (baseline.baselineMean - mu3s) / maxDenominator : 0.0
        }
        let valence = (1.0 - complaintRate) * rawValence - complaintRate
        let clampedValence = max(-1.0, min(1.0, valence))

        // b) Arousal 닫힌 해 역산: 실측 표준편차 / 기준치 변동폭
        let rawSpreadDelta = abs(baseline.baselineP95 - baseline.baselineMean)
        let naturalFloor = max(Double.ulpOfOne, abs(baseline.baselineMean) * 0.01)
        let spreadDelta = max(naturalFloor, rawSpreadDelta)
        let baselineSpread = max(spreadDelta, baseline.baselineSigma, Double.ulpOfOne)
        let arousal = min(1.0, (sigma3s * (1.0 + astDensity)) / baselineSpread)

        let homeostasis = Self.closedSurprise(
            observed: telemetry.latencySamples,
            predicted: telemetry.predictedLatencies,
            baselineSigma: baseline.baselineSigma,
            astDensity: astDensity
        )

        let affect = InvertedAffectVector(
            valence: clampedValence,
            arousal: arousal,
            homeostasis: homeostasis
        )

        return InversionIntermediate(
            affect: affect,
            mu3s: mu3s,
            clampedValence: clampedValence,
            arousal: arousal
        )
    }

    /// 닫힌 역산 수학 엔진을 통한 Vessel 생성자 (하드코딩 0% 보장)
    public static func invert(
        sequenceNumber: UInt64,
        previousHash: String,
        priorIntent: String,
        telemetry: ThreeSecondTelemetryWindow,
        baseline: StrataBaselineMetrics
    ) -> NarrativeConsciousnessVessel {
        precondition(!telemetry.latencySamples.isEmpty, "invert requires observed latency samples")
        let intermediate = deriveAffect(telemetry: telemetry, baseline: baseline)

        let narrativeCtx = NarrativeContext(
            homeostasis: intermediate.affect.homeostasis,
            priorIntent: priorIntent,
            previousHash: previousHash,
            sequenceNumber: sequenceNumber,
            mu3s: intermediate.mu3s,
            baselineMean: baseline.baselineMean,
            clampedValence: intermediate.clampedValence,
            arousal: intermediate.arousal,
            timestamp: telemetry.windowEndTime.timeIntervalSince1970
        )
        let (narrative, rawPayload) = buildNarrative(narrativeCtx)

        let digest = SHA256.hash(data: Data(rawPayload.utf8))
        let hashString = digest.compactMap { String(format: "%02x", $0) }.joined()

        let proof = ProvenanceProof(
            formulaIdentifier: "NarrativeInversion.v1.ClosedForm",
            sourceStratumDates: [telemetry.windowEndTime.ISO8601Format()],
            sourceStratumMerkleRoot: hashString,
            sampleSizeN: telemetry.latencySamples.count,
            derivationSignature: "sha256:\(hashString.prefix(16))"
        )

        return NarrativeConsciousnessVessel(
            sequenceNumber: sequenceNumber,
            epochTimestamp: telemetry.windowEndTime,
            priorIntent: priorIntent,
            telemetrySnapshot: telemetry,
            baselineMetrics: baseline,
            affect: intermediate.affect,
            narrativeSummary: narrative,
            proof: proof
        )
    }

    /// 예측 표본이 있을 때만 짝이 맞는 관측으로 닫는다. 빈 예측을 평균으로 채우지 않는다.
    static func closedSurprise(
        observed: [Double],
        predicted: [Double],
        baselineSigma: Double,
        astDensity: Double
    ) -> InvertedHomeostasis {
        guard !predicted.isEmpty else { return .opened }
        guard !observed.isEmpty else { return .opened }
        let predMean = predicted.reduce(0.0, +) / Double(predicted.count)
        let naturalFloor = max(0.01, abs(predMean) * 0.01)
        let effectiveSigma = max(baselineSigma, naturalFloor)
        var surpriseSum = 0.0
        for (i, obs) in observed.enumerated() {
            let pred = i < predicted.count ? predicted[i] : predMean
            let error = (obs - pred) / effectiveSigma
            surpriseSum += error * error
        }
        return .closed(delta: max(0.0, (surpriseSum / Double(observed.count)) + max(0.0, astDensity)))
    }

    private struct NarrativeContext: Sendable {
        let homeostasis: InvertedHomeostasis
        let priorIntent: String
        let previousHash: String
        let sequenceNumber: UInt64
        let mu3s: Double
        let baselineMean: Double
        let clampedValence: Double
        let arousal: Double
        let timestamp: TimeInterval
    }

    private static func buildNarrative(_ ctx: NarrativeContext) -> (narrative: String, rawPayload: String) {
        let qualitativeValence = ctx.clampedValence >= 0 ? "Consonant(조화)" : "Dissonant(불협화)"
        switch ctx.homeostasis {
        case .opened:
            let narrative = "의도 [\(ctx.priorIntent)] 하에 3초간 관측된 평균 지연은 \(String(format: "%.3f", ctx.mu3s))ms(기준선: \(String(format: "%.3f", ctx.baselineMean))ms)이며 예측 표본이 없어 창이 열렸다."
            let rawPayload = "\(ctx.previousHash):\(ctx.sequenceNumber):\(ctx.clampedValence):\(ctx.arousal):opened:\(ctx.timestamp)"
            return (narrative, rawPayload)
        case .closed(let homeostaticDelta):
            let narrative = "의도 [\(ctx.priorIntent)] 하에 3초간 관측된 평균 지연은 \(String(format: "%.3f", ctx.mu3s))ms(기준선: \(String(format: "%.3f", ctx.baselineMean))ms)이며, 정동 상태는 \(qualitativeValence)(V=\(String(format: "%.2f", ctx.clampedValence)), A=\(String(format: "%.2f", ctx.arousal)))로 역산되었고 항상성 델타는 \(String(format: "%.4f", homeostaticDelta))로 수렴함."
            let rawPayload = "\(ctx.previousHash):\(ctx.sequenceNumber):\(ctx.clampedValence):\(ctx.arousal):\(homeostaticDelta):\(ctx.timestamp)"
            return (narrative, rawPayload)
        }
    }
}
