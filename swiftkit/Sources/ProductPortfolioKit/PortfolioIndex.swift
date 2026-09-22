import Foundation
import StateRootKit

/// `~/.product-portfolio` 루트 (products + evaluations).
public enum PortfolioPaths {
    public static var defaultRoot: URL {
        StateRootKit.url(for: ".product-portfolio")
    }

    public static func products(root: URL = defaultRoot) -> URL {
        root.appendingPathComponent("products", isDirectory: true)
    }

    public static func evaluations(root: URL = defaultRoot) -> URL {
        root.appendingPathComponent("evaluations", isDirectory: true)
    }
}

/// 상품 카드 + 최신 평가 요약 조인 뷰.
public struct PortfolioCard: Codable, Equatable, Identifiable, Sendable {
    public var id: String { product.slug }

    public let product: Product
    public let evaluation: EvaluationSummary?
    public let salesCopyComplete: Bool
    public let hasEvaluation: Bool

    public init(product: Product, evaluation: EvaluationSummary?) {
        self.product = product
        self.evaluation = evaluation
        self.salesCopyComplete = !ProductField.sales.isMissing(in: product)
        self.hasEvaluation = evaluation != nil
    }
}

public struct PortfolioStatus: Codable, Equatable, Sendable {
    public let products: CatalogStatus
    public let evaluationCount: Int
    public let productsWithoutEvaluation: Int
    public let salesIncomplete: Int
    public let averageOverallScore: Double?
    public let visuals: VisualStats

    public init(
        products: CatalogStatus,
        evaluationCount: Int,
        productsWithoutEvaluation: Int,
        salesIncomplete: Int,
        averageOverallScore: Double?,
        visuals: VisualStats = VisualStats()
    ) {
        self.products = products
        self.evaluationCount = evaluationCount
        self.productsWithoutEvaluation = productsWithoutEvaluation
        self.salesIncomplete = salesIncomplete
        self.averageOverallScore = averageOverallScore
        self.visuals = visuals
    }
}

/// products + evaluations 를 slug 로 묶는 인덱스.
public struct PortfolioIndex: Sendable {
    public let productStore: ProductStore
    public let evaluationStore: EvaluationStore

    public init(portfolioRoot: URL = PortfolioPaths.defaultRoot) throws {
        productStore = try ProductStore(rootDirectory: portfolioRoot)
        evaluationStore = EvaluationStore(root: PortfolioPaths.evaluations(root: portfolioRoot))
    }

    public init(productStore: ProductStore, evaluationStore: EvaluationStore) {
        self.productStore = productStore
        self.evaluationStore = evaluationStore
    }

    public func cards() throws -> [PortfolioCard] {
        let evalBySlug = Dictionary(
            uniqueKeysWithValues: try evaluationStore.list().map { ($0.slug, $0) }
        )
        return try productStore.list().map { product in
            PortfolioCard(product: product, evaluation: evalBySlug[product.slug])
        }
    }

    public func status() throws -> PortfolioStatus {
        let products = try productStore.list()
        let catalog = CatalogStatus(products: products)
        let evals = try evaluationStore.list()
        let evalSlugs = Set(evals.map(\.slug))
        let without = products.filter { !evalSlugs.contains($0.slug) }.count
        let salesIncomplete = products.filter { ProductField.sales.isMissing(in: $0) }.count
        let average: Double?
        if evals.isEmpty {
            average = nil
        } else {
            average = evals.map(\.overallScore).reduce(0, +) / Double(evals.count)
        }
        return PortfolioStatus(
            products: catalog,
            evaluationCount: evals.count,
            productsWithoutEvaluation: without,
            salesIncomplete: salesIncomplete,
            averageOverallScore: average,
            visuals: VisualStats.tally(from: products)
        )
    }
}

/// 관측 가능한 Product 필드만으로 평가 **초안** 점수를 만든다 (사람 검토 전제).
public enum EvaluationDraftFactory {
    public static func scores(from product: Product) throws -> DimensionScores {
        let completeness = Double(product.readiness)
        let salesFilled = !ProductField.sales.isMissing(in: product)
        let roleFilled = !ProductField.role.isMissing(in: product)
        let sellability: Double = {
            if salesFilled && roleFilled { return min(5, max(completeness, 3)) }
            if roleFilled { return min(3, completeness) }
            return min(2, completeness)
        }()
        let quality = completeness
        let differentiation: Double = product.classification == .productCandidate
            ? min(4, completeness)
            : min(2, completeness)
        return try DimensionScores(
            sellability: sellability,
            quality: quality,
            completeness: completeness,
            differentiation: differentiation
        )
    }

    public static func make(
        from product: Product,
        evaluatedAt: Date = Date(),
        summary: String = "Product 관측치 기반 초안(검토 필요)"
    ) throws -> Evaluation {
        try Evaluation(
            slug: product.slug,
            evaluatedAt: evaluatedAt,
            scores: scores(from: product),
            strengths: roleFilledStrengths(product),
            improvements: missingImprovements(product),
            summary: summary
        )
    }

    private static func roleFilledStrengths(_ product: Product) -> [String] {
        ProductField.role.isMissing(in: product) ? [] : ["역할 한 줄이 정의되어 있음"]
    }

    private static func missingImprovements(_ product: Product) throws -> [Improvement] {
        var items: [Improvement] = []
        if ProductField.sales.isMissing(in: product) {
            items.append(
                try Improvement(
                    text: "buyerPersona / salesAngle / priceIdea 판매 카피를 채운다",
                    severity: .high,
                    suggestedAction: "product-showcasectl set \(product.slug) --buyer-persona …"
                )
            )
        }
        if ProductField.role.isMissing(in: product) {
            items.append(
                try Improvement(
                    text: "README 역할 한 줄을 role 에 채운다",
                    severity: .medium,
                    suggestedAction: "product-showcasectl sync --apps-root … 또는 set --role"
                )
            )
        }
        if product.readiness < 3 {
            items.append(
                try Improvement(
                    text: "테스트·소스 기준으로 readiness 가 낮다",
                    severity: .medium,
                    suggestedAction: "구현·테스트 보강 후 readiness 재산정"
                )
            )
        }
        return items
    }
}
