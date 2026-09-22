import Foundation
@_exported import ProductPortfolioCoreKit
@_exported import ProductPortfolioStoreKit

public enum EvaluationError: Error, Equatable, LocalizedError, Sendable {
    case invalidScore(dimension: String, value: Double)
    case invalidSlug(String)
    case notFound(String)
    case emptyImprovement

    public var errorDescription: String? {
        switch self {
        case let .invalidScore(dimension, value):
            return "\(dimension) 점수 \(value)는 0에서 \(Int(ScoreScale.signalMax)) 사이여야 합니다."
        case let .invalidSlug(slug):
            return "안전하지 않은 제품 slug입니다: \(slug)"
        case let .notFound(slug):
            return "평가서를 찾을 수 없습니다: \(slug)"
        case .emptyImprovement:
            return "개선점 내용은 비워 둘 수 없습니다."
        }
    }
}

public struct DimensionScores: Codable, Equatable, Sendable {
    public let sellability: Double
    public let quality: Double
    public let completeness: Double
    public let differentiation: Double

    public init(
        sellability: Double,
        quality: Double,
        completeness: Double,
        differentiation: Double
    ) throws {
        let values = [
            ("sellability", sellability),
            ("quality", quality),
            ("completeness", completeness),
            ("differentiation", differentiation),
        ]
        if let invalid = values.first(where: { !(0...ScoreScale.signalMax).contains($0.1) }) {
            throw EvaluationError.invalidScore(dimension: invalid.0, value: invalid.1)
        }

        self.sellability = sellability
        self.quality = quality
        self.completeness = completeness
        self.differentiation = differentiation
    }

    public var average: Double {
        (sellability + quality + completeness + differentiation) / 4
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            sellability: container.decode(Double.self, forKey: .sellability),
            quality: container.decode(Double.self, forKey: .quality),
            completeness: container.decode(Double.self, forKey: .completeness),
            differentiation: container.decode(Double.self, forKey: .differentiation)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case sellability, quality, completeness, differentiation
    }
}

public enum ImprovementSeverity: String, Codable, CaseIterable, Sendable {
    case low
    case medium
    case high
    case critical
}

public struct Improvement: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let text: String
    public let severity: ImprovementSeverity
    public let suggestedAction: String?

    public init(
        id: UUID = UUID(),
        text: String,
        severity: ImprovementSeverity,
        suggestedAction: String? = nil
    ) throws {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else {
            throw EvaluationError.emptyImprovement
        }
        self.id = id
        self.text = normalizedText
        self.severity = severity
        self.suggestedAction = suggestedAction?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(UUID.self, forKey: .id),
            text: container.decode(String.self, forKey: .text),
            severity: container.decode(ImprovementSeverity.self, forKey: .severity),
            suggestedAction: container.decodeIfPresent(String.self, forKey: .suggestedAction)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id, text, severity, suggestedAction
    }
}

public struct Evaluation: Codable, Equatable, Identifiable, Sendable {
    public var id: String { "\(slug)@\(evaluatedAt.timeIntervalSinceReferenceDate)" }

    public let slug: String
    public let evaluatedAt: Date
    public let scores: DimensionScores
    public let strengths: [String]
    public let improvements: [Improvement]
    public let summary: String

    public init(
        slug: String,
        evaluatedAt: Date,
        scores: DimensionScores,
        strengths: [String],
        improvements: [Improvement],
        summary: String
    ) throws {
        guard Self.isValid(slug: slug) else {
            throw EvaluationError.invalidSlug(slug)
        }
        self.slug = slug
        self.evaluatedAt = evaluatedAt
        self.scores = scores
        self.strengths = strengths
        self.improvements = improvements
        self.summary = summary
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            slug: container.decode(String.self, forKey: .slug),
            evaluatedAt: container.decode(Date.self, forKey: .evaluatedAt),
            scores: container.decode(DimensionScores.self, forKey: .scores),
            strengths: container.decode([String].self, forKey: .strengths),
            improvements: container.decode([Improvement].self, forKey: .improvements),
            summary: container.decode(String.self, forKey: .summary)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case slug, evaluatedAt, scores, strengths, improvements, summary
    }

    public var overallScore: Double { scores.average }

    public static func isValid(slug: String) -> Bool {
        !slug.isEmpty && slug.range(
            of: #"^[a-z0-9]+(?:-[a-z0-9]+)*$"#,
            options: .regularExpression
        ) != nil
    }

    public func appending(improvement: Improvement) throws -> Evaluation {
        try Evaluation(
            slug: slug,
            evaluatedAt: evaluatedAt,
            scores: scores,
            strengths: strengths,
            improvements: improvements + [improvement],
            summary: summary
        )
    }
}

public struct EvaluationDocument: Codable, Equatable, Sendable {
    public let current: Evaluation
    public let history: [Evaluation]

    public init(current: Evaluation, history: [Evaluation]) {
        self.current = current
        self.history = history
    }

    public var timeline: [Evaluation] {
        (history + [current]).sorted { $0.evaluatedAt < $1.evaluatedAt }
    }
}

public struct EvaluationSummary: Codable, Equatable, Identifiable, Sendable {
    public var id: String { slug }

    public let slug: String
    public let evaluatedAt: Date
    public let overallScore: Double
    public let improvementCount: Int

    public init(evaluation: Evaluation) {
        slug = evaluation.slug
        evaluatedAt = evaluation.evaluatedAt
        overallScore = evaluation.overallScore
        improvementCount = evaluation.improvements.count
    }
}
