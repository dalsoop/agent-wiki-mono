import Foundation

/// 제품 readiness(0–5)를 신호 기반으로 다시 계산한다.
/// 목표: 시드·enrich 로 4점에 몰린 분포를 완화한다.
public enum ReadinessRecomputer {
    public struct Signals: Codable, Equatable, Sendable {
        public let roleLength: Int
        public let salesFieldCount: Int
        public let hasEvaluation: Bool
        /// batch-seed 초안이 아닌 수동/심층 평가 여부.
        public let hasManualEvaluation: Bool
        public let hasScreenshots: Bool
        public let hasPackaging: Bool

        public init(
            roleLength: Int,
            salesFieldCount: Int,
            hasEvaluation: Bool,
            hasManualEvaluation: Bool = false,
            hasScreenshots: Bool,
            hasPackaging: Bool
        ) {
            self.roleLength = max(0, roleLength)
            self.salesFieldCount = max(0, min(3, salesFieldCount))
            self.hasEvaluation = hasEvaluation
            self.hasManualEvaluation = hasManualEvaluation
            self.hasScreenshots = hasScreenshots
            self.hasPackaging = hasPackaging
        }

        public var hasRole: Bool { roleLength >= 4 }
    }

    public struct Change: Codable, Equatable, Sendable {
        public let slug: String
        public let from: Int
        public let to: Int
        public let signals: Signals

        public init(slug: String, from: Int, to: Int, signals: Signals) {
            self.slug = slug
            self.from = from
            self.to = to
            self.signals = signals
        }
    }

    public struct Result: Codable, Equatable, Sendable {
        public let dryRun: Bool
        public let total: Int
        public let changed: Int
        public let unchanged: Int
        public let snapshotPath: String?
        public let changes: [Change]
        public let histogramBefore: [String: Int]
        public let histogramAfter: [String: Int]

        public init(
            dryRun: Bool,
            total: Int,
            changed: Int,
            unchanged: Int,
            snapshotPath: String?,
            changes: [Change],
            histogramBefore: [String: Int],
            histogramAfter: [String: Int]
        ) {
            self.dryRun = dryRun
            self.total = total
            self.changed = changed
            self.unchanged = unchanged
            self.snapshotPath = snapshotPath
            self.changes = changes
            self.histogramBefore = histogramBefore
            self.histogramAfter = histogramAfter
        }
    }

    public struct Options: Equatable, Sendable {
        public var evaluationsDirectory: URL?
        public var appsRoot: URL?
        public var dryRun: Bool
        public var writeSnapshot: Bool
        /// nil 이면 전체 분류.
        public var classification: ProductClassification?
        /// 비어 있지 않으면 해당 slug 만.
        public var slugs: Set<String>

        public init(
            evaluationsDirectory: URL? = nil,
            appsRoot: URL? = nil,
            dryRun: Bool = true,
            writeSnapshot: Bool = true,
            classification: ProductClassification? = nil,
            slugs: Set<String> = []
        ) {
            self.evaluationsDirectory = evaluationsDirectory
            self.appsRoot = appsRoot
            self.dryRun = dryRun
            self.writeSnapshot = writeSnapshot
            self.classification = classification
            self.slugs = slugs
        }
    }

    /// 점수 규칙 (합 상한 5)
    /// - role 길이: 4–29 → +1 / 30+ → +2 (상한 2 — 60+ 로 5점 과밀 방지)
    /// - 판매 필드 전부 의미 있게 채움: +1
    /// - **수동** 평가만 +1 (batch-seed 초안은 가산 없음 → 4점 과밀 완화)
    /// - 스크린샷 경로 1개 이상: +1
    /// - Packaging 단독 가산 없음
    public static func score(from signals: Signals) -> Int {
        var value = 0
        switch signals.roleLength {
        case 0..<4:
            break
        case 4..<30:
            value += 1
        default:
            value += 2
        }
        if signals.salesFieldCount >= 3 { value += 1 }
        if signals.hasManualEvaluation { value += 1 }
        if signals.hasScreenshots { value += 1 }
        return min(5, max(0, value))
    }

    public static func signals(
        for product: Product,
        evaluationsDirectory: URL?,
        appsRoot: URL?
    ) -> Signals {
        let role = product.role.trimmingCharacters(in: .whitespacesAndNewlines)
        let roleLength = isMeaningful(role) ? role.count : 0
        let salesFieldCount = [
            product.buyerPersona,
            product.salesAngle,
            product.priceIdea,
        ].filter(isMeaningful).count
        let evaluationURL = evaluationsDirectory.map {
            $0.appendingPathComponent(product.slug).appendingPathExtension("json")
        }
        let hasEvaluation = evaluationURL.map {
            FileManager.default.fileExists(atPath: $0.path)
        } ?? false
        let hasManualEvaluation: Bool = {
            guard hasEvaluation, let evaluationURL else { return false }
            return isManualEvaluation(at: evaluationURL)
        }()
        let hasScreenshots = product.hasAnyScreenshotAsset
        let hasPackaging = packagingExists(for: product.slug, appsRoot: appsRoot)
        return Signals(
            roleLength: roleLength,
            salesFieldCount: salesFieldCount,
            hasEvaluation: hasEvaluation,
            hasManualEvaluation: hasManualEvaluation,
            hasScreenshots: hasScreenshots,
            hasPackaging: hasPackaging
        )
    }

    /// evaluation JSON 의 current.summary 가 draft(`batch-seed`·`signal-v1`)가 아니면 수동으로 본다.
    public static func isManualEvaluation(at url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url),
              let object = PortfolioJSON.raw(from: data),
              let root = object as? [String: Any]
        else {
            return false
        }
        let summary: String
        if let current = root["current"] as? [String: Any],
           let text = current["summary"] as? String {
            summary = text
        } else if let text = root["summary"] as? String {
            summary = text
        } else {
            return true
        }
        return EvaluationSignalComposer.isManualSummary(summary)
    }

    public static func recompute(
        in store: ProductStore,
        options: Options = Options()
    ) throws -> Result {
        let allProducts = try store.list()
        let products = allProducts.filter { product in
            if let classification = options.classification,
               product.classification != classification {
                return false
            }
            if !options.slugs.isEmpty, !options.slugs.contains(product.slug) {
                return false
            }
            return true
        }
        let evaluationsDirectory = options.evaluationsDirectory
            ?? store.rootDirectory.appendingPathComponent(
                "evaluations",
                isDirectory: true
            )

        var changes: [Change] = []
        var before: [Int: Int] = [:]
        var after: [Int: Int] = [:]
        var updatedProducts: [(Product, Int)] = []

        for product in products {
            before[product.readiness, default: 0] += 1
            let signal = signals(
                for: product,
                evaluationsDirectory: evaluationsDirectory,
                appsRoot: options.appsRoot
            )
            let next = score(from: signal)
            after[next, default: 0] += 1
            if next != product.readiness {
                changes.append(
                    Change(
                        slug: product.slug,
                        from: product.readiness,
                        to: next,
                        signals: signal
                    )
                )
                updatedProducts.append((product, next))
            }
        }

        var snapshotPath: String?
        if !options.dryRun, !updatedProducts.isEmpty {
            if options.writeSnapshot {
                let snapshotURL = try snapshotProductsDirectory(
                    from: store.productsDirectory,
                    under: store.rootDirectory
                )
                snapshotPath = snapshotURL.path
            }
            for (product, readiness) in updatedProducts {
                var next = product
                next.readiness = readiness
                try store.save(next)
            }
        }

        return Result(
            dryRun: options.dryRun,
            total: products.count,
            changed: changes.count,
            unchanged: products.count - changes.count,
            snapshotPath: snapshotPath,
            changes: changes.sorted { $0.slug < $1.slug },
            histogramBefore: histogramStrings(before),
            histogramAfter: histogramStrings(after)
        )
    }

    public static func isMeaningful(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 4 else { return false }
        let lowered = trimmed.lowercased()
        let placeholders: Set<String> = [
            "todo", "tbd", "n/a", "na", "none", "없음", "미정",
            "placeholder", "lorem", "test",
        ]
        if placeholders.contains(lowered) { return false }
        // enrich 기본문 중 너무 일반적인 것만 제외하지 않는다 — 채워져 있으면 신호로 인정
        return true
    }

    public static func packagingExists(for slug: String, appsRoot: URL?) -> Bool {
        guard let appsRoot else { return false }
        let candidates = [
            appsRoot.appendingPathComponent(slug).appendingPathComponent("Packaging"),
            appsRoot.appendingPathComponent("\(slug)-swift").appendingPathComponent("Packaging"),
            appsRoot.appendingPathComponent(slug.replacingOccurrences(of: "-swift", with: ""))
                .appendingPathComponent("Packaging"),
        ]
        return candidates.contains {
            FileManager.default.fileExists(atPath: $0.path)
        }
    }

    public static func snapshotProductsDirectory(
        from productsDirectory: URL,
        under rootDirectory: URL,
        now: Date = Date()
    ) throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: now)
        let backupRoot = rootDirectory
            .appendingPathComponent("backups", isDirectory: true)
            .appendingPathComponent("products-\(stamp)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: backupRoot.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: backupRoot.path) {
            try FileManager.default.removeItem(at: backupRoot)
        }
        try FileManager.default.copyItem(at: productsDirectory, to: backupRoot)
        return backupRoot
    }

    private static func histogramStrings(_ counts: [Int: Int]) -> [String: Int] {
        Dictionary(uniqueKeysWithValues: counts.map { ("\($0.key)", $0.value) })
    }
}
