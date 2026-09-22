import Foundation

public struct RuleOfThreeCandidate: Codable, Sendable, Equatable {
    public var utilityName: String
    public var occurrences: [String]
    public var proposedKitName: String
    public var rationale: String

    public init(
        utilityName: String,
        occurrences: [String],
        proposedKitName: String,
        rationale: String
    ) {
        self.utilityName = utilityName
        self.occurrences = occurrences
        self.proposedKitName = proposedKitName
        self.rationale = rationale
    }
}

public struct GovernanceSummary: Codable, Sendable, Equatable {
    public var processComplianceRate: Double
    public var ruleOfThreeCandidatesCount: Int
    public var ruleOfThreeCandidates: [RuleOfThreeCandidate]
    public var tetrahedronMaturityRate: Double
    public var totalNodesCount: Int
    public var totalEdgesCount: Int

    public init(
        processComplianceRate: Double,
        ruleOfThreeCandidatesCount: Int,
        ruleOfThreeCandidates: [RuleOfThreeCandidate] = [],
        tetrahedronMaturityRate: Double,
        totalNodesCount: Int,
        totalEdgesCount: Int
    ) {
        self.processComplianceRate = processComplianceRate
        self.ruleOfThreeCandidatesCount = ruleOfThreeCandidatesCount
        self.ruleOfThreeCandidates = ruleOfThreeCandidates
        self.tetrahedronMaturityRate = tetrahedronMaturityRate
        self.totalNodesCount = totalNodesCount
        self.totalEdgesCount = totalEdgesCount
    }
}

public struct ArchitectureMetadata: Codable, Sendable, Equatable {
    public var monorepoVersion: String
    public var scannedAt: Date
    public var gitSha: String
    public var scannerVersion: String
    public var governanceSummary: GovernanceSummary

    public init(
        monorepoVersion: String,
        scannedAt: Date = Date(),
        gitSha: String,
        scannerVersion: String = "1.0.0",
        governanceSummary: GovernanceSummary
    ) {
        self.monorepoVersion = monorepoVersion
        self.scannedAt = scannedAt
        self.gitSha = gitSha
        self.scannerVersion = scannerVersion
        self.governanceSummary = governanceSummary
    }
}
