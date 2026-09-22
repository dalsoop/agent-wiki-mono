import Foundation

/// apps/ 아래에서 제품 스크린샷 후보를 찾아 `screenshotPaths` 를 채운다.
public enum ScreenshotPathSeeder {
    public static let preferredDirectories = [
        "store-assets/out",
        "store-assets",
        "docs/evidence",
        "docs/assets",
        "docs/screenshots",
        "screenshots",
        "Marketing",
        "docs",
    ]

    public static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp",
    ]

    /// Asset Catalog / 아이콘 등 스크린샷으로 쓰지 않을 경로 조각.
    public static let excludedPathFragments = [
        ".imageset/",
        "AppIcon",
        "Assets.xcassets",
        "/DerivedData/",
        "/.build/",
        "/node_modules/",
    ]

    public struct Options: Equatable, Sendable {
        public var appsRoot: URL
        public var dryRun: Bool
        public var replaceExisting: Bool
        public var maxPerProduct: Int

        public init(
            appsRoot: URL,
            dryRun: Bool = true,
            replaceExisting: Bool = false,
            maxPerProduct: Int = 6
        ) {
            self.appsRoot = appsRoot
            self.dryRun = dryRun
            self.replaceExisting = replaceExisting
            self.maxPerProduct = max(1, maxPerProduct)
        }
    }

    public struct Change: Codable, Equatable, Sendable {
        public let slug: String
        public let appDirectory: String?
        public let beforeCount: Int
        public let afterPaths: [String]

        public init(
            slug: String,
            appDirectory: String?,
            beforeCount: Int,
            afterPaths: [String]
        ) {
            self.slug = slug
            self.appDirectory = appDirectory
            self.beforeCount = beforeCount
            self.afterPaths = afterPaths
        }
    }

    public struct Result: Codable, Equatable, Sendable {
        public let dryRun: Bool
        public let total: Int
        public let updated: Int
        public let skipped: Int
        public let unmatched: Int
        public let changes: [Change]

        public init(
            dryRun: Bool,
            total: Int,
            updated: Int,
            skipped: Int,
            unmatched: Int,
            changes: [Change]
        ) {
            self.dryRun = dryRun
            self.total = total
            self.updated = updated
            self.skipped = skipped
            self.unmatched = unmatched
            self.changes = changes
        }
    }

    public static func seed(
        in store: ProductStore,
        options: Options
    ) throws -> Result {
        let products = try store.list()
        var updated = 0
        var skipped = 0
        var unmatched = 0
        var changes: [Change] = []

        for product in products {
            let existing = product.screenshotPaths.filter {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            if !existing.isEmpty, !options.replaceExisting {
                skipped += 1
                continue
            }

            guard let appDir = resolveAppDirectory(
                slug: product.slug,
                appsRoot: options.appsRoot
            ) else {
                unmatched += 1
                continue
            }

            let found = discoverScreenshots(
                in: appDir,
                maxCount: options.maxPerProduct
            )
            if found.isEmpty {
                unmatched += 1
                continue
            }

            let paths = found.map(\.path)
            if paths == existing {
                skipped += 1
                continue
            }

            changes.append(
                Change(
                    slug: product.slug,
                    appDirectory: appDir.lastPathComponent,
                    beforeCount: existing.count,
                    afterPaths: paths
                )
            )
            updated += 1
            if !options.dryRun {
                var next = product
                next.screenshotPaths = paths
                try store.save(next)
            }
        }

        return Result(
            dryRun: options.dryRun,
            total: products.count,
            updated: updated,
            skipped: skipped,
            unmatched: unmatched,
            changes: changes.sorted { $0.slug < $1.slug }
        )
    }

    public static func resolveAppDirectory(
        slug: String,
        appsRoot: URL
    ) -> URL? {
        let candidates = [
            appsRoot.appendingPathComponent(slug, isDirectory: true),
            appsRoot.appendingPathComponent("\(slug)-swift", isDirectory: true),
            appsRoot.appendingPathComponent(
                slug.replacingOccurrences(of: "-swift", with: ""),
                isDirectory: true
            ),
        ]
        return candidates.first {
            FileManager.default.fileExists(atPath: $0.path)
        }
    }

    public static func discoverScreenshots(
        in appDirectory: URL,
        maxCount: Int = 6
    ) -> [URL] {
        var collected: [URL] = []
        var seen = Set<String>()

        for relative in preferredDirectories {
            let dir = appDirectory.appendingPathComponent(relative, isDirectory: true)
            guard FileManager.default.fileExists(atPath: dir.path) else { continue }
            let files = listImages(under: dir)
            for file in files {
                let key = file.standardizedFileURL.path
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                collected.append(file.standardizedFileURL)
                if collected.count >= maxCount { return collected }
            }
        }
        return collected
    }

    private static func listImages(under directory: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var results: [URL] = []
        for case let url as URL in enumerator {
            let path = url.path
            if excludedPathFragments.contains(where: { path.contains($0) }) {
                continue
            }
            let ext = url.pathExtension.lowercased()
            guard imageExtensions.contains(ext) else { continue }
            var isFile: AnyObject?
            try? (url as NSURL).getResourceValue(&isFile, forKey: .isRegularFileKey)
            if let flag = isFile as? Bool, !flag { continue }
            results.append(url)
        }

        return results.sorted { lhs, rhs in
            let l = score(path: lhs.path)
            let r = score(path: rhs.path)
            if l != r { return l > r }
            return lhs.lastPathComponent < rhs.lastPathComponent
        }
    }

    /// hero/detail/overview 등 마케팅에 가까운 이름을 우선.
    private static func score(path: String) -> Int {
        let lower = path.lowercased()
        var value = 0
        if lower.contains("/store-assets/out/") { value += 50 }
        if lower.contains("/store-assets/") { value += 30 }
        if lower.contains("/docs/evidence/") { value += 25 }
        if lower.contains("/docs/assets/") { value += 20 }
        if lower.contains("hero") { value += 15 }
        if lower.contains("detail") { value += 12 }
        if lower.contains("overview") { value += 10 }
        if lower.contains("banner") { value += 8 }
        if lower.contains("demo") { value += 5 }
        if lower.hasSuffix(".png") { value += 3 }
        if lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg") { value += 2 }
        return value
    }
}
