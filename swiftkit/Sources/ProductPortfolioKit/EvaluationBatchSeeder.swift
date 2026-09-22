import Foundation

/// showcase `~/.product-portfolio/products/*.json` 과 키를 맞춘 최소 DTO.
/// showcase Core를 의존하지 않아 패키지 결합을 피한다.
public struct PortfolioProductSnapshot: Codable, Equatable, Sendable {
    public let slug: String
    public let role: String
    public let classification: String
    public let buyerPersona: String
    public let salesAngle: String
    public let priceIdea: String
    public let categories: [String]
    public let readiness: Int
    public let screenshotPaths: [String]

    public struct Pitch: Equatable, Sendable {
        public var role: String
        public var classification: String
        public var buyerPersona: String
        public var salesAngle: String
        public var priceIdea: String
        public var categories: [String]

        public init(
            role: String = "",
            classification: String = "product-candidate",
            buyerPersona: String = "",
            salesAngle: String = "",
            priceIdea: String = "",
            categories: [String] = []
        ) {
            self.role = role
            self.classification = classification
            self.buyerPersona = buyerPersona
            self.salesAngle = salesAngle
            self.priceIdea = priceIdea
            self.categories = categories
        }
    }

    public struct Surface: Equatable, Sendable {
        public var readiness: Int
        public var screenshotPaths: [String]

        public init(readiness: Int = 0, screenshotPaths: [String] = []) {
            self.readiness = readiness
            self.screenshotPaths = screenshotPaths
        }
    }

    public init(slug: String, pitch: Pitch = Pitch(), surface: Surface = Surface()) {
        self.slug = slug
        self.role = pitch.role
        self.classification = pitch.classification
        self.buyerPersona = pitch.buyerPersona
        self.salesAngle = pitch.salesAngle
        self.priceIdea = pitch.priceIdea
        self.categories = pitch.categories
        self.readiness = surface.readiness
        self.screenshotPaths = surface.screenshotPaths
    }

    public var hasScreenshotAsset: Bool {
        screenshotPaths.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private enum CodingKeys: String, CodingKey {
        case slug, role, classification, buyerPersona, salesAngle, priceIdea, categories, readiness
        case screenshotPaths
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        slug = try values.decode(String.self, forKey: .slug)
        role = try values.decodeIfPresent(String.self, forKey: .role) ?? ""
        classification = try values.decodeIfPresent(String.self, forKey: .classification) ?? "product-candidate"
        buyerPersona = try values.decodeIfPresent(String.self, forKey: .buyerPersona) ?? ""
        salesAngle = try values.decodeIfPresent(String.self, forKey: .salesAngle) ?? ""
        priceIdea = try values.decodeIfPresent(String.self, forKey: .priceIdea) ?? ""
        categories = try values.decodeIfPresent([String].self, forKey: .categories) ?? []
        readiness = try values.decodeIfPresent(Int.self, forKey: .readiness) ?? 0
        screenshotPaths = try values.decodeIfPresent([String].self, forKey: .screenshotPaths) ?? []
    }
}

public struct BatchSeedResult: Codable, Equatable, Sendable {
    public let created: [String]
    public let skipped: [String]
    public let dryRun: Bool

    public init(created: [String], skipped: [String], dryRun: Bool) {
        self.created = created
        self.skipped = skipped
        self.dryRun = dryRun
    }

    public var createdCount: Int { created.count }
    public var skippedCount: Int { skipped.count }
}

/// - Important: **deprecated.** 메타데이터 길이 기반 초안은 변별력이 없다.
///   신규 경로는 `EvaluationSignalComposer` / CLI `signal-compose` 를 쓴다.
///   이 타입은 기존 테스트·호환을 위해 남긴다.
public enum EvaluationBatchSeeder {
    public static let summaryPrefix = "batch-seed v1"

    public static func loadProducts(from productsDirectory: URL) throws -> [PortfolioProductSnapshot] {
        guard FileManager.default.fileExists(atPath: productsDirectory.path) else { return [] }
        let urls = try FileManager.default.contentsOfDirectory(
            at: productsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        return try urls
            .filter { $0.pathExtension == "json" }
            .map { try JSONDecoder().decode(PortfolioProductSnapshot.self, from: Data(contentsOf: $0)) }
            .sorted { $0.slug < $1.slug }
    }

    public static func score(from product: PortfolioProductSnapshot) throws -> DimensionScores {
        let readiness = Double(min(max(product.readiness, 0), 5))
        let quality = readiness

        var completeness = 2.0
        let role = product.role.trimmingCharacters(in: .whitespacesAndNewlines)
        if !role.isEmpty, !role.contains("역할 한 줄") {
            completeness += 1.5
            if role.count >= 20 { completeness += 0.5 }
        }
        completeness = min(5, completeness + readiness * 0.2)

        var filled = 0
        if !product.buyerPersona.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { filled += 1 }
        if !product.salesAngle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { filled += 1 }
        if !product.priceIdea.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { filled += 1 }
        let sellability = min(5, 1.5 + Double(filled) + (readiness >= 4 ? 0.5 : 0))

        var differentiation = 2.0
        if product.classification == "product-candidate" { differentiation += 1.0 }
        if !product.categories.isEmpty { differentiation += 0.5 }
        differentiation = min(5, differentiation + readiness * 0.2)

        return try DimensionScores(
            sellability: round1(sellability),
            quality: round1(quality),
            completeness: round1(completeness),
            differentiation: round1(differentiation)
        )
    }

    public static func makeEvaluation(
        from product: PortfolioProductSnapshot,
        evaluatedAt: Date = Date()
    ) throws -> Evaluation {
        let scores = try score(from: product)
        let role = product.role.trimmingCharacters(in: .whitespacesAndNewlines)
        let strengths = role.isEmpty || role.contains("역할 한 줄") ? [] : [role]
        let summary =
            "\(summaryPrefix) · readiness=\(product.readiness) · class=\(product.classification)"
        return try Evaluation(
            slug: product.slug,
            evaluatedAt: evaluatedAt,
            scores: scores,
            strengths: strengths,
            improvements: [],
            summary: summary
        )
    }

    public static func seedBatch(
        products: [PortfolioProductSnapshot],
        into store: EvaluationStore,
        minReadiness: Int = 4,
        classification: String? = "product-candidate",
        dryRun: Bool = false,
        evaluatedAt: Date = Date()
    ) throws -> BatchSeedResult {
        var created: [String] = []
        var skipped: [String] = []

        for product in products {
            guard product.readiness >= minReadiness else {
                skipped.append(product.slug)
                continue
            }
            if let classification, product.classification != classification {
                skipped.append(product.slug)
                continue
            }
            if store.exists(slug: product.slug) {
                skipped.append(product.slug)
                continue
            }
            if dryRun {
                created.append(product.slug)
                continue
            }
            let evaluation = try makeEvaluation(from: product, evaluatedAt: evaluatedAt)
            try store.save(evaluation)
            created.append(product.slug)
        }

        return BatchSeedResult(created: created, skipped: skipped, dryRun: dryRun)
    }

    private static func round1(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }
}
