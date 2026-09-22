import Foundation

/// 관측 신호 묶음. 점수는 이 값만으로 결정된다(카피 길이 금지).
public struct EvaluationSignalBundle: Equatable, Sendable {
    public var slug: String
    public var classification: String
    public var salesFieldsFilled: Int
    public var hasRealScreenshot: Bool
    public var hasCategories: Bool

    public var repoExists: Bool
    public var hasTests: Bool
    public var hasPackaging: Bool
    public var hasCliIdentity: Bool
    public var hasLicense: Bool

    public var installed: Bool
    public var built: Bool
    public var staleInstall: Bool
    /// `stub` | `developed` | 기타
    public var completenessLabel: String?
    /// `unknown` | `passed` | `warning` | `blocked` | `rolled-back`
    public var auditState: String?

    /// nil = 미스캔
    public var hardenedRuntime: Bool?
    public var notarized: Bool?
    /// app-quality-loop 0...100, 없으면 nil
    public var qualityLoopScore: Double?

    public struct Sales: Equatable, Sendable {
        public var classification: String
        public var salesFieldsFilled: Int
        public var hasRealScreenshot: Bool
        public var hasCategories: Bool

        public init(
            classification: String = "product-candidate",
            salesFieldsFilled: Int = 0,
            hasRealScreenshot: Bool = false,
            hasCategories: Bool = false
        ) {
            self.classification = classification
            self.salesFieldsFilled = salesFieldsFilled
            self.hasRealScreenshot = hasRealScreenshot
            self.hasCategories = hasCategories
        }
    }

    public struct Repo: Equatable, Sendable {
        public var exists: Bool
        public var hasTests: Bool
        public var hasPackaging: Bool
        public var hasCliIdentity: Bool
        public var hasLicense: Bool

        public init(
            exists: Bool = false,
            hasTests: Bool = false,
            hasPackaging: Bool = false,
            hasCliIdentity: Bool = false,
            hasLicense: Bool = false
        ) {
            self.exists = exists
            self.hasTests = hasTests
            self.hasPackaging = hasPackaging
            self.hasCliIdentity = hasCliIdentity
            self.hasLicense = hasLicense
        }
    }

    public struct Install: Equatable, Sendable {
        public var installed: Bool
        public var built: Bool
        public var staleInstall: Bool
        public var completenessLabel: String?
        public var auditState: String?

        public init(
            installed: Bool = false,
            built: Bool = false,
            staleInstall: Bool = false,
            completenessLabel: String? = nil,
            auditState: String? = nil
        ) {
            self.installed = installed
            self.built = built
            self.staleInstall = staleInstall
            self.completenessLabel = completenessLabel
            self.auditState = auditState
        }
    }

    public struct Release: Equatable, Sendable {
        public var hardenedRuntime: Bool?
        public var notarized: Bool?
        public var qualityLoopScore: Double?

        public init(
            hardenedRuntime: Bool? = nil,
            notarized: Bool? = nil,
            qualityLoopScore: Double? = nil
        ) {
            self.hardenedRuntime = hardenedRuntime
            self.notarized = notarized
            self.qualityLoopScore = qualityLoopScore
        }
    }

    public init(
        slug: String,
        sales: Sales = Sales(),
        repo: Repo = Repo(),
        install: Install = Install(),
        release: Release = Release()
    ) {
        self.slug = slug
        self.classification = sales.classification
        self.salesFieldsFilled = max(0, min(3, sales.salesFieldsFilled))
        self.hasRealScreenshot = sales.hasRealScreenshot
        self.hasCategories = sales.hasCategories
        self.repoExists = repo.exists
        self.hasTests = repo.hasTests
        self.hasPackaging = repo.hasPackaging
        self.hasCliIdentity = repo.hasCliIdentity
        self.hasLicense = repo.hasLicense
        self.installed = install.installed
        self.built = install.built
        self.staleInstall = install.staleInstall
        self.completenessLabel = install.completenessLabel
        self.auditState = install.auditState
        self.hardenedRuntime = release.hardenedRuntime
        self.notarized = release.notarized
        self.qualityLoopScore = release.qualityLoopScore
    }
}

public struct SignalComposeResult: Codable, Equatable, Sendable {
    public let created: [String]
    public let updated: [String]
    public let skipped: [String]
    public let dryRun: Bool
    public let items: [SignalComposeItem]

    public init(
        created: [String],
        updated: [String],
        skipped: [String],
        dryRun: Bool,
        items: [SignalComposeItem]
    ) {
        self.created = created
        self.updated = updated
        self.skipped = skipped
        self.dryRun = dryRun
        self.items = items
    }
}

public struct SignalComposeItem: Codable, Equatable, Sendable {
    public let slug: String
    public let action: String
    public let overallScore: Double
    public let confidence: Double
    public let scores: DimensionScoresDTO
    public let improvementCount: Int
    public let summary: String

    public init(
        slug: String,
        action: String,
        overallScore: Double,
        confidence: Double,
        scores: DimensionScores,
        improvementCount: Int,
        summary: String
    ) {
        self.slug = slug
        self.action = action
        self.overallScore = overallScore
        self.confidence = confidence
        self.scores = DimensionScoresDTO(scores)
        self.improvementCount = improvementCount
        self.summary = summary
    }
}

/// Codable 스냅샷(테스트·JSON 출력용).
public struct DimensionScoresDTO: Codable, Equatable, Sendable {
    public let sellability: Double
    public let quality: Double
    public let completeness: Double
    public let differentiation: Double

    public init(_ scores: DimensionScores) {
        sellability = scores.sellability
        quality = scores.quality
        completeness = scores.completeness
        differentiation = scores.differentiation
    }
}
