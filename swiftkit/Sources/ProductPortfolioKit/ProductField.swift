import Foundation

/// 제품 카드에서 “비어 있음 / 집계 / CLI --missing”의 단일 정본.
/// 문자열 스위치 복붙 대신 이 enum 한 곳에서 판정한다.
public enum ProductField: String, CaseIterable, Codable, Sendable {
    case role
    case persona
    case angle
    case price
    case categories
    case screenshots
    /// persona · angle · price 중 하나라도 비면 판매 카피 미완.
    case sales

    /// CLI `--missing` 토큰.
    public var cliToken: String { rawValue }

    public static var missingCLITokens: [String] {
        allCases.map(\.cliToken)
    }

    public static func parseMissingToken(_ raw: String) -> ProductField? {
        allCases.first { $0.cliToken == raw }
    }

    public func isMissing(in product: Product) -> Bool {
        switch self {
        case .role:
            ProductCopy.isBlank(product.role)
        case .persona:
            ProductCopy.isBlank(product.buyerPersona)
        case .angle:
            ProductCopy.isBlank(product.salesAngle)
        case .price:
            ProductCopy.isBlank(product.priceIdea)
        case .categories:
            product.categories.isEmpty
        case .screenshots:
            !product.hasAnyScreenshotAsset
        case .sales:
            ProductField.persona.isMissing(in: product)
                || ProductField.angle.isMissing(in: product)
                || ProductField.price.isMissing(in: product)
        }
    }
}

/// status JSON 집계 — 필드 객체에서 파생.
public struct MissingFieldCounts: Codable, Equatable, Sendable {
    public var role: Int
    public var persona: Int
    public var angle: Int
    public var price: Int
    public var categories: Int
    public var screenshots: Int
    public var sales: Int

    public init(
        role: Int = 0,
        persona: Int = 0,
        angle: Int = 0,
        price: Int = 0,
        categories: Int = 0,
        screenshots: Int = 0,
        sales: Int = 0
    ) {
        self.role = role
        self.persona = persona
        self.angle = angle
        self.price = price
        self.categories = categories
        self.screenshots = screenshots
        self.sales = sales
    }

    public static func tally(from products: [Product]) -> MissingFieldCounts {
        var counts = MissingFieldCounts()
        for product in products {
            if ProductField.role.isMissing(in: product) { counts.role += 1 }
            if ProductField.persona.isMissing(in: product) { counts.persona += 1 }
            if ProductField.angle.isMissing(in: product) { counts.angle += 1 }
            if ProductField.price.isMissing(in: product) { counts.price += 1 }
            if ProductField.categories.isMissing(in: product) { counts.categories += 1 }
            if ProductField.screenshots.isMissing(in: product) { counts.screenshots += 1 }
            if ProductField.sales.isMissing(in: product) { counts.sales += 1 }
        }
        return counts
    }
}

public struct CatalogStatus: Codable, Equatable, Sendable {
    public let total: Int
    public let byReadiness: [String: Int]
    public let byClassification: [String: Int]
    public let missing: MissingFieldCounts

    public init(products: [Product]) {
        total = products.count
        var readiness: [String: Int] = [:]
        for level in Product.readinessRange {
            readiness[String(level)] = 0
        }
        var classification: [String: Int] = [:]
        for item in ProductClassification.allCases {
            classification[item.rawValue] = 0
        }
        for product in products {
            readiness[String(product.readiness), default: 0] += 1
            classification[product.classification.rawValue, default: 0] += 1
        }
        byReadiness = readiness
        byClassification = classification
        missing = MissingFieldCounts.tally(from: products)
    }
}
