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

// MARK: - 4. 불변 증명서 (Cryptographic Provenance Token)
/// 임의의 하드코딩 생성을 원천 차단하기 위해, 계수는 반드시 유효한 ProvenanceProof를 지녀야만 함.
public struct ProvenanceProof: Codable, Sendable, Equatable {
    public let formulaIdentifier: String
    public let derivedTimestamp: Date
    public let sourceStratumDates: [String]
    public let sourceStratumMerkleRoot: String
    public let sampleSizeN: Int
    public let derivationSignature: String

    public init(
        formulaIdentifier: String,
        sourceStratumDates: [String],
        sourceStratumMerkleRoot: String,
        sampleSizeN: Int,
        derivationSignature: String
    ) {
        self.formulaIdentifier = formulaIdentifier
        self.derivedTimestamp = Date()
        self.sourceStratumDates = sourceStratumDates
        self.sourceStratumMerkleRoot = sourceStratumMerkleRoot
        self.sampleSizeN = sampleSizeN
        self.derivationSignature = derivationSignature
    }
}
