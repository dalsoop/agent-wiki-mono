import Foundation

public struct SeedResult: Codable, Equatable, Sendable {
    public let created: Int
    public let skipped: Int

    public init(created: Int, skipped: Int) {
        self.created = created
        self.skipped = skipped
    }
}

public struct EnrichResult: Codable, Equatable, Sendable {
    public let updated: Int
    public let unchanged: Int

    public init(updated: Int, unchanged: Int) {
        self.updated = updated
        self.unchanged = unchanged
    }
}

public enum InventorySeeder {
    private struct InventoryItem: Decodable {
        let app: String
        let readmeRole: String?
        let classification: ProductClassification
        let readiness: Int

        private enum CodingKeys: String, CodingKey {
            case app
            case readmeRole = "readme_role"
            case classification = "v0_class"
            case readiness = "v0_readiness"
        }
    }

    /// inventory JSON → Product. 판매 카피는 비운 채 관측 필드만 채운다.
    public static func seed(from source: URL, into store: ProductStore) throws -> SeedResult {
        let items = try JSONDecoder().decode([InventoryItem].self, from: Data(contentsOf: source))
        var created = 0
        var skipped = 0

        for item in items {
            if store.contains(slug: item.app) {
                skipped += 1
                continue
            }
            let displayName = ProductGenerator.displayName(fromSlug: item.app)
            let product = try Product(
                names: .init(slug: item.app, nameKo: displayName, nameEn: displayName),
                pitch: .init(
                    role: ProductCopy.plainRole(item.readmeRole ?? ""),
                    classification: item.classification,
                    buyerPersona: "",
                    salesAngle: "",
                    categories: [],
                    priceIdea: ""
                ),
                surface: .init(readiness: item.readiness, screenshotPaths: [])
            )
            try store.add(product)
            created += 1
        }
        return SeedResult(created: created, skipped: skipped)
    }

    /// role 마크다운만 정리 (판매 템플릿 주입 없음).
    public static func enrichExisting(in store: ProductStore) throws -> EnrichResult {
        var updated = 0
        var unchanged = 0
        for product in try store.list() {
            let (next, changed) = try ProductCopy.cleaningRoleMarkdown(product)
            if changed {
                try store.save(next)
                updated += 1
            } else {
                unchanged += 1
            }
        }
        return EnrichResult(updated: updated, unchanged: unchanged)
    }
}
