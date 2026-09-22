import Foundation

/// App Store Connect 에 붙여넣기용 로컬 메타 스냅샷 (실제 ASC 업로드 아님).
public struct ShowcaseASCRecord: Codable, Equatable, Sendable {
    public var slug: String
    public var name: String
    public var subtitle: String
    public var description: String
    public var promotionalText: String
    public var whatsNew: String
    public var keywords: String
    public var primaryCategory: String
    public var priceLabel: String
    public var primaryCTA: String
    public var macScreenshotPaths: [String]
    public var iosScreenshotPaths: [String]
    public var iconPath: String?
    public var supportURL: String
    public var marketingURL: String
    public var privacyPolicyURL: String
    public var exportedAt: String

    public struct Identity: Equatable, Sendable {
        public var slug: String
        public var name: String
        public var subtitle: String
        public var primaryCategory: String
        public var priceLabel: String
        public var primaryCTA: String

        public init(
            slug: String,
            name: String,
            subtitle: String,
            primaryCategory: String,
            priceLabel: String,
            primaryCTA: String
        ) {
            self.slug = slug
            self.name = name
            self.subtitle = subtitle
            self.primaryCategory = primaryCategory
            self.priceLabel = priceLabel
            self.primaryCTA = primaryCTA
        }
    }

    public struct Copy: Equatable, Sendable {
        public var description: String
        public var promotionalText: String
        public var whatsNew: String
        public var keywords: String

        public init(
            description: String,
            promotionalText: String,
            whatsNew: String,
            keywords: String
        ) {
            self.description = description
            self.promotionalText = promotionalText
            self.whatsNew = whatsNew
            self.keywords = keywords
        }
    }

    public struct Assets: Equatable, Sendable {
        public var macScreenshotPaths: [String]
        public var iosScreenshotPaths: [String]
        public var iconPath: String?

        public init(
            macScreenshotPaths: [String],
            iosScreenshotPaths: [String],
            iconPath: String?
        ) {
            self.macScreenshotPaths = macScreenshotPaths
            self.iosScreenshotPaths = iosScreenshotPaths
            self.iconPath = iconPath
        }
    }

    public struct Links: Equatable, Sendable {
        public var supportURL: String
        public var marketingURL: String
        public var privacyPolicyURL: String
        public var exportedAt: String

        public init(
            supportURL: String = "",
            marketingURL: String = "",
            privacyPolicyURL: String = "",
            exportedAt: String = ISO8601DateFormatter().string(from: Date())
        ) {
            self.supportURL = supportURL
            self.marketingURL = marketingURL
            self.privacyPolicyURL = privacyPolicyURL
            self.exportedAt = exportedAt
        }
    }

    public init(identity: Identity, copy: Copy, assets: Assets, links: Links = Links()) {
        self.slug = identity.slug
        self.name = identity.name
        self.subtitle = identity.subtitle
        self.description = copy.description
        self.promotionalText = copy.promotionalText
        self.whatsNew = copy.whatsNew
        self.keywords = copy.keywords
        self.primaryCategory = identity.primaryCategory
        self.priceLabel = identity.priceLabel
        self.primaryCTA = identity.primaryCTA
        self.macScreenshotPaths = assets.macScreenshotPaths
        self.iosScreenshotPaths = assets.iosScreenshotPaths
        self.iconPath = assets.iconPath
        self.supportURL = links.supportURL
        self.marketingURL = links.marketingURL
        self.privacyPolicyURL = links.privacyPolicyURL
        self.exportedAt = links.exportedAt
    }
}

public struct ShowcaseASCExportResult: Codable, Equatable, Sendable {
    public var directory: String
    public var indexPath: String
    public var records: [String]
    public var count: Int

    public init(directory: String, indexPath: String, records: [String], count: Int) {
        self.directory = directory
        self.indexPath = indexPath
        self.records = records
        self.count = count
    }
}

public enum ShowcaseASCExport {
    public static func defaultOutputRoot() -> URL {
        ShowcasePackageReader.defaultRoot()
            .appendingPathComponent("asc-export", isDirectory: true)
    }

    public static func record(
        product: Product,
        listing: StoreListing,
        packageRoot: URL = ShowcasePackageReader.defaultRoot()
    ) -> ShowcaseASCRecord {
        let macShots = ShowcaseAppStoreHTML.preferredShots(
            for: product,
            platform: .mac,
            listing: listing,
            limit: 10
        ).map(\.path)
        let iosShots = ShowcaseAppStoreHTML.preferredShots(
            for: product,
            platform: .ios,
            listing: listing,
            limit: 10
        ).map(\.path)

        return ShowcaseASCRecord(
            identity: .init(
                slug: product.slug,
                name: listing.name.isEmpty
                    ? (product.nameKo.isEmpty ? product.slug : product.nameKo)
                    : listing.name,
                subtitle: listing.subtitle,
                primaryCategory: listing.category.isEmpty
                    ? (product.categories.first ?? "")
                    : listing.category,
                priceLabel: listing.priceLabel.isEmpty ? product.priceIdea : listing.priceLabel,
                primaryCTA: listing.primaryCTA
            ),
            copy: .init(
                description: listing.description,
                promotionalText: listing.promotionalText,
                whatsNew: listing.whatsNew,
                keywords: listing.keywords
            ),
            assets: .init(
                macScreenshotPaths: macShots,
                iosScreenshotPaths: iosShots,
                iconPath: listing.iconPath
            )
        )
    }

    /// `showcase/asc-export/` 아래 제품별 JSON + index.json + 요약 md.
    public static func export(
        products: [Product],
        packageRoot: URL = ShowcasePackageReader.defaultRoot(),
        outputRoot: URL? = nil,
        listingStore: StoreListingStore? = nil
    ) throws -> ShowcaseASCExportResult {
        let out = outputRoot ?? packageRoot.appendingPathComponent("asc-export", isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        let listings = listingStore ?? StoreListingStore(
            rootDirectory: packageRoot.appendingPathComponent("listings", isDirectory: true)
        )

        var records: [ShowcaseASCRecord] = []
        var paths: [String] = []
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

        for product in products {
            let landing = ShowcasePackageReader.landingMarkdown(
                slug: product.slug,
                root: packageRoot
            )
            let listing = try listings.loadOrSeed(
                product: product,
                landingMarkdown: landing,
                persistSeed: false
            )
            let rec = record(product: product, listing: listing, packageRoot: packageRoot)
            records.append(rec)
            let file = out.appendingPathComponent("\(product.slug).json")
            var data = try encoder.encode(rec)
            data.append(0x0A)
            try data.write(to: file, options: .atomic)
            paths.append(file.path)

            // 사람용 한 장 요약
            let md = markdown(for: rec)
            try md.write(
                to: out.appendingPathComponent("\(product.slug).md"),
                atomically: true,
                encoding: .utf8
            )
        }

        let indexURL = out.appendingPathComponent("index.json")
        var indexData = try encoder.encode(records)
        indexData.append(0x0A)
        try indexData.write(to: indexURL, options: .atomic)

        let summary = """
        # App Store Connect 메타 export

        - 생성: \(ISO8601DateFormatter().string(from: Date()))
        - 건수: \(records.count)
        - 실제 ASC 업로드 아님. 카피·샷 경로 스냅샷.

        \(records.map { "- [\($0.slug)](\($0.slug).md) — \($0.name)" }.joined(separator: "\n"))
        """
        try summary.write(
            to: out.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )

        return ShowcaseASCExportResult(
            directory: out.path,
            indexPath: indexURL.path,
            records: paths,
            count: records.count
        )
    }

    private static func markdown(for rec: ShowcaseASCRecord) -> String {
        """
        # \(rec.name)

        - slug: `\(rec.slug)`
        - subtitle: \(rec.subtitle)
        - category: \(rec.primaryCategory)
        - price: \(rec.priceLabel)
        - CTA: \(rec.primaryCTA)
        - keywords: \(rec.keywords)

        ## Description

        \(rec.description)

        ## Promotional Text

        \(rec.promotionalText)

        ## What's New

        \(rec.whatsNew)

        ## Mac screenshots (\(rec.macScreenshotPaths.count))

        \(rec.macScreenshotPaths.map { "- `\($0)`" }.joined(separator: "\n"))

        ## iPhone screenshots (\(rec.iosScreenshotPaths.count))

        \(rec.iosScreenshotPaths.map { "- `\($0)`" }.joined(separator: "\n"))

        ## Icon

        \(rec.iconPath.map { "`\($0)`" } ?? "(없음)")

        ---
        exportedAt: \(rec.exportedAt)
        """
    }
}
