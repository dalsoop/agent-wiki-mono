import Foundation
import CryptoKit
@_exported import RuleMiningEngineKit

// MARK: - 1. 불변 증명서 (Cryptographic Provenance Token)
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

// MARK: - 2. Rule 1 완전 봉인 계수 모델 (CertifiedDataDrivenCoefficients)
public struct CertifiedDataDrivenCoefficients: Codable, Sendable, Equatable {
    public let layerWeightL1: Double
    public let layerWeightL2: Double
    public let layerWeightL3: Double
    public let layerWeightL4: Double
    public let l1SpeedCutoffMs: Double
    public let hesitationPenaltyFactor: Double
    public let proof: ProvenanceProof

    public init(
        layerWeightL1: Double,
        layerWeightL2: Double,
        layerWeightL3: Double,
        layerWeightL4: Double,
        l1SpeedCutoffMs: Double,
        hesitationPenaltyFactor: Double,
        proof: ProvenanceProof
    ) {
        self.layerWeightL1 = layerWeightL1
        self.layerWeightL2 = layerWeightL2
        self.layerWeightL3 = layerWeightL3
        self.layerWeightL4 = layerWeightL4
        self.l1SpeedCutoffMs = l1SpeedCutoffMs
        self.hesitationPenaltyFactor = hesitationPenaltyFactor
        self.proof = proof
    }
}

// MARK: - 3. 단방향 흐름 보장 유도 에러
public enum SSOTDerivationError: Error, LocalizedError {
    case zeroStratumDataViolation(reason: String)
    case invalidProvenanceMerkleRoot
    case signatureVerificationFailed

    public var errorDescription: String? {
        switch self {
        case .zeroStratumDataViolation(let r): return "Rule 1 Violation: Cannot derive coefficients without empirical stratum data: \(r)"
        case .invalidProvenanceMerkleRoot: return "Provenance Integrity Violation: Merkle root mismatch"
        case .signatureVerificationFailed: return "Security Violation: Derivation signature does not match inputs"
        }
    }
}
