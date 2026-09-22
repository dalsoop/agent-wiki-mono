import Foundation

/// 쇼케이스 패키지 한 제품의 문서·샷 상태.
public struct ShowcasePackageItemStatus: Codable, Equatable, Sendable {
    public let slug: String
    public let nameKo: String
    public let readiness: Int
    public let classification: String
    public let screenshotPathCount: Int
    public let existingImageCount: Int
    public let hasLanding: Bool
    public let hasFirstRun: Bool
    public let landingPath: String
    public let firstRunPath: String

    public struct Identity: Equatable, Sendable {
        public var slug: String
        public var nameKo: String
        public var readiness: Int
        public var classification: String

        public init(slug: String, nameKo: String, readiness: Int, classification: String) {
            self.slug = slug
            self.nameKo = nameKo
            self.readiness = readiness
            self.classification = classification
        }
    }

    public struct Package: Equatable, Sendable {
        public var screenshotPathCount: Int
        public var existingImageCount: Int
        public var hasLanding: Bool
        public var hasFirstRun: Bool
        public var landingPath: String
        public var firstRunPath: String

        public init(
            screenshotPathCount: Int,
            existingImageCount: Int,
            hasLanding: Bool,
            hasFirstRun: Bool,
            landingPath: String,
            firstRunPath: String
        ) {
            self.screenshotPathCount = screenshotPathCount
            self.existingImageCount = existingImageCount
            self.hasLanding = hasLanding
            self.hasFirstRun = hasFirstRun
            self.landingPath = landingPath
            self.firstRunPath = firstRunPath
        }
    }

    public init(identity: Identity, package: Package) {
        self.slug = identity.slug
        self.nameKo = identity.nameKo
        self.readiness = identity.readiness
        self.classification = identity.classification
        self.screenshotPathCount = package.screenshotPathCount
        self.existingImageCount = package.existingImageCount
        self.hasLanding = package.hasLanding
        self.hasFirstRun = package.hasFirstRun
        self.landingPath = package.landingPath
        self.firstRunPath = package.firstRunPath
    }

    public var isComplete: Bool {
        hasLanding && hasFirstRun && existingImageCount > 0
    }
}

/// 쇼케이스 패키지 전체 상태.
public struct ShowcasePackageStatus: Codable, Equatable, Sendable {
    public let root: String
    public let total: Int
    public let complete: Int
    public let missingLanding: Int
    public let missingFirstRun: Int
    public let missingImages: Int
    public let items: [ShowcasePackageItemStatus]

    public init(
        root: String,
        total: Int,
        complete: Int,
        missingLanding: Int,
        missingFirstRun: Int,
        missingImages: Int,
        items: [ShowcasePackageItemStatus]
    ) {
        self.root = root
        self.total = total
        self.complete = complete
        self.missingLanding = missingLanding
        self.missingFirstRun = missingFirstRun
        self.missingImages = missingImages
        self.items = items
    }
}

/// lineup.json 한 행.
public struct ShowcaseLineupEntry: Codable, Equatable, Sendable {
    public let slug: String
    public let nameKo: String
    public let nameEn: String
    public let role: String
    public let buyerPersona: String
    public let salesAngle: String
    public let priceIdea: String
    public let categories: [String]
    public let readiness: Int
    public let screenshotPaths: [String]
    public let existingImagePaths: [String]
    public let hasLanding: Bool
    public let hasFirstRun: Bool
    public let landingPath: String
    public let firstRunPath: String

    public init(from product: Product, packageRoot: URL) {
        let landing = ShowcasePackageReader.landingURL(slug: product.slug, root: packageRoot)
        let firstRun = ShowcasePackageReader.firstRunURL(slug: product.slug, root: packageRoot)
        let images = ShowcasePackageReader.displayableImageURLs(for: product)
        self.slug = product.slug
        self.nameKo = product.nameKo
        self.nameEn = product.nameEn
        self.role = product.role
        self.buyerPersona = product.buyerPersona
        self.salesAngle = product.salesAngle
        self.priceIdea = product.priceIdea
        self.categories = product.categories
        self.readiness = product.readiness
        self.screenshotPaths = product.screenshotPaths
        self.existingImagePaths = images.map(\.path)
        self.hasLanding = FileManager.default.fileExists(atPath: landing.path)
        self.hasFirstRun = FileManager.default.fileExists(atPath: firstRun.path)
        self.landingPath = landing.path
        self.firstRunPath = firstRun.path
    }
}

public struct ShowcaseLineupDocument: Codable, Equatable, Sendable {
    public let generatedAt: String
    public let criteria: String
    public let count: Int
    public let packageRoot: String
    public let products: [ShowcaseLineupEntry]

    public init(
        generatedAt: String,
        criteria: String,
        count: Int,
        packageRoot: String,
        products: [ShowcaseLineupEntry]
    ) {
        self.generatedAt = generatedAt
        self.criteria = criteria
        self.count = count
        self.packageRoot = packageRoot
        self.products = products
    }
}

public struct ShowcaseExportResult: Codable, Equatable, Sendable {
    public let packageRoot: String
    public let lineupJSONPath: String
    public let lineupMarkdownPath: String
    public let count: Int
    public let writtenAt: String

    public init(
        packageRoot: String,
        lineupJSONPath: String,
        lineupMarkdownPath: String,
        count: Int,
        writtenAt: String
    ) {
        self.packageRoot = packageRoot
        self.lineupJSONPath = lineupJSONPath
        self.lineupMarkdownPath = lineupMarkdownPath
        self.count = count
        self.writtenAt = writtenAt
    }
}

/// 쇼케이스 패키지 상태·lineup 내보내기.
public enum ShowcasePackageExporter {
    public static func filterProducts(
        _ products: [Product],
        minReadiness: Int,
        classification: ProductClassification?
    ) -> [Product] {
        products.filter { product in
            product.readiness >= minReadiness
                && (classification == nil || product.classification == classification)
        }
        .sorted { $0.slug < $1.slug }
    }

    public static func status(
        products: [Product],
        packageRoot: URL = ShowcasePackageReader.defaultRoot()
    ) -> ShowcasePackageStatus {
        let items = products.map { product -> ShowcasePackageItemStatus in
            let landing = ShowcasePackageReader.landingURL(slug: product.slug, root: packageRoot)
            let firstRun = ShowcasePackageReader.firstRunURL(slug: product.slug, root: packageRoot)
            let images = ShowcasePackageReader.displayableImageURLs(for: product)
            return ShowcasePackageItemStatus(
                identity: .init(
                    slug: product.slug,
                    nameKo: product.nameKo,
                    readiness: product.readiness,
                    classification: product.classification.rawValue
                ),
                package: .init(
                    screenshotPathCount: product.screenshotPaths.filter {
                        !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    }.count,
                    existingImageCount: images.count,
                    hasLanding: FileManager.default.fileExists(atPath: landing.path),
                    hasFirstRun: FileManager.default.fileExists(atPath: firstRun.path),
                    landingPath: landing.path,
                    firstRunPath: firstRun.path
                )
            )
        }
        return ShowcasePackageStatus(
            root: packageRoot.path,
            total: items.count,
            complete: items.filter(\.isComplete).count,
            missingLanding: items.filter { !$0.hasLanding }.count,
            missingFirstRun: items.filter { !$0.hasFirstRun }.count,
            missingImages: items.filter { $0.existingImageCount == 0 }.count,
            items: items
        )
    }

    public static func exportLineup(
        products: [Product],
        packageRoot: URL = ShowcasePackageReader.defaultRoot(),
        criteria: String
    ) throws -> ShowcaseExportResult {
        let fm = FileManager.default
        try fm.createDirectory(at: packageRoot, withIntermediateDirectories: true)
        try fm.createDirectory(
            at: packageRoot.appendingPathComponent("landings", isDirectory: true),
            withIntermediateDirectories: true
        )
        try fm.createDirectory(
            at: packageRoot.appendingPathComponent("first-run", isDirectory: true),
            withIntermediateDirectories: true
        )

        let entries = products.map { ShowcaseLineupEntry(from: $0, packageRoot: packageRoot) }
        let stamp = ISO8601DateFormatter().string(from: Date())
        let document = ShowcaseLineupDocument(
            generatedAt: stamp,
            criteria: criteria,
            count: entries.count,
            packageRoot: packageRoot.path,
            products: entries
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonURL = packageRoot.appendingPathComponent("lineup.json")
        try encoder.encode(document).write(to: jsonURL, options: .atomic)

        let mdURL = packageRoot.appendingPathComponent("lineup.md")
        try markdown(document).write(to: mdURL, atomically: true, encoding: .utf8)

        return ShowcaseExportResult(
            packageRoot: packageRoot.path,
            lineupJSONPath: jsonURL.path,
            lineupMarkdownPath: mdURL.path,
            count: entries.count,
            writtenAt: stamp
        )
    }

    public static func markdown(_ document: ShowcaseLineupDocument) -> String {
        var lines: [String] = [
            "# 쇼케이스 라인업",
            "",
            "생성: \(document.generatedAt) · \(document.count)개",
            "조건: \(document.criteria)",
            "루트: `\(document.packageRoot)`",
            "",
            "| # | 이름 | slug | r | 샷 | 랜딩 | 첫실행 |",
            "|---|---|---|---|---|---|---|",
        ]
        for (index, product) in document.products.enumerated() {
            let name = product.nameKo.isEmpty ? product.slug : product.nameKo
            lines.append(
                "| \(index + 1) | \(name) | `\(product.slug)` | \(product.readiness) | \(product.existingImagePaths.count) | \(product.hasLanding ? "Y" : "n") | \(product.hasFirstRun ? "Y" : "n") |"
            )
        }
        lines += ["", "## 상세", ""]
        for product in document.products {
            let name = product.nameKo.isEmpty ? product.slug : product.nameKo
            lines.append("### \(name) (`\(product.slug)`)")
            lines.append("- role: \(product.role)")
            lines.append("- persona: \(product.buyerPersona)")
            lines.append("- angle: \(product.salesAngle)")
            lines.append("- price: \(product.priceIdea)")
            lines.append("- landing: `\(product.landingPath)` \(product.hasLanding ? "✓" : "✗")")
            lines.append("- first-run: `\(product.firstRunPath)` \(product.hasFirstRun ? "✓" : "✗")")
            lines.append("- images: \(product.existingImagePaths.count)")
            lines.append("")
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
