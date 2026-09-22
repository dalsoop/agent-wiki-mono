import Foundation

public enum EvaluationSignalCollector {
    public struct RouterAppState: Equatable, Sendable {
        public var slug: String
        public var installed: Bool
        public var built: Bool
        public var staleInstall: Bool
        public var completenessLabel: String?
        public var auditState: String?
        public var bundleName: String?
        public var displayName: String?
        public var processName: String?

        public struct Status: Equatable, Sendable {
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

        public struct Names: Equatable, Sendable {
            public var bundleName: String?
            public var displayName: String?
            public var processName: String?

            public init(
                bundleName: String? = nil,
                displayName: String? = nil,
                processName: String? = nil
            ) {
                self.bundleName = bundleName
                self.displayName = displayName
                self.processName = processName
            }
        }

        public init(slug: String, status: Status = Status(), names: Names = Names()) {
            self.slug = slug
            self.installed = status.installed
            self.built = status.built
            self.staleInstall = status.staleInstall
            self.completenessLabel = status.completenessLabel
            self.auditState = status.auditState
            self.bundleName = names.bundleName
            self.displayName = names.displayName
            self.processName = names.processName
        }
    }

    public static func loadRouterStates(from url: URL) -> [String: RouterAppState] {
        guard let data = try? Data(contentsOf: url),
              let object = PortfolioJSON.raw(from: data)
        else { return [:] }

        guard let rows = routerRows(from: object) else { return [:] }

        var map: [String: RouterAppState] = [:]
        for row in rows {
            let app = row["app"] as? [String: Any] ?? [:]
            guard let slug = app["slug"] as? String, !slug.isEmpty else { continue }
            let audit = row["audit"] as? [String: Any]
            map[slug] = RouterAppState(
                slug: slug,
                status: .init(
                    installed: row["installed"] as? Bool ?? false,
                    built: row["built"] as? Bool ?? false,
                    staleInstall: row["staleInstall"] as? Bool ?? false,
                    completenessLabel: app["completeness"] as? String,
                    auditState: audit?["state"] as? String
                ),
                names: .init(
                    bundleName: app["bundleName"] as? String,
                    displayName: app["displayName"] as? String,
                    processName: app["processName"] as? String
                )
            )
        }
        return map
    }

    public static func collect(
        products: [PortfolioProductSnapshot],
        appsRoot: URL?,
        routerStates: [String: RouterAppState] = [:],
        applicationsDirectory: URL = URL(filePath: "/Applications", directoryHint: .isDirectory),
        probeReleaseGates: Bool = false,
        qualityLoopScores: [String: Double] = [:],
        fileManager: FileManager = .default
    ) -> [EvaluationSignalBundle] {
        products.map { product in
            bundle(
                for: product,
                appsRoot: appsRoot,
                routerStates: routerStates,
                applicationsDirectory: applicationsDirectory,
                probeReleaseGates: probeReleaseGates,
                qualityLoopScores: qualityLoopScores,
                fileManager: fileManager
            )
        }
    }

    private static func routerRows(from object: Any) -> [[String: Any]]? {
        if let list = object as? [[String: Any]] {
            return list
        }
        if let dict = object as? [String: Any], let apps = dict["apps"] as? [[String: Any]] {
            return apps
        }
        if let dict = object as? [String: Any], let apps = dict["apps"] as? [String: [String: Any]] {
            return Array(apps.values)
        }
        return nil
    }

    private static func bundle(
        for product: PortfolioProductSnapshot,
        appsRoot: URL?,
        routerStates: [String: RouterAppState],
        applicationsDirectory: URL,
        probeReleaseGates: Bool,
        qualityLoopScores: [String: Double],
        fileManager: FileManager
    ) -> EvaluationSignalBundle {
        let router = routerStates[product.slug]
            ?? routerStates[product.slug.replacingOccurrences(of: "-swift", with: "")]
        let repo = EvaluationSignalRepoShape.inspect(
            slug: product.slug,
            appsRoot: appsRoot,
            fileManager: fileManager
        )
        let salesFilled = [
            product.buyerPersona,
            product.salesAngle,
            product.priceIdea,
        ].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count

        let gates = releaseGates(
            router: router,
            probe: probeReleaseGates,
            applicationsDirectory: applicationsDirectory,
            fileManager: fileManager
        )
        let qualityScore =
            qualityLoopScores[product.slug]
            ?? qualityLoopScores[product.slug.replacingOccurrences(of: "-swift", with: "")]

        return EvaluationSignalBundle(
            slug: product.slug,
            sales: .init(
                classification: product.classification,
                salesFieldsFilled: salesFilled,
                hasRealScreenshot: product.hasScreenshotAsset,
                hasCategories: !product.categories.isEmpty
            ),
            repo: .init(
                exists: repo.exists,
                hasTests: repo.tests,
                hasPackaging: repo.packaging,
                hasCliIdentity: repo.cliIdentity,
                hasLicense: repo.license
            ),
            install: .init(
                installed: router?.installed ?? false,
                built: router?.built ?? false,
                staleInstall: router?.staleInstall ?? false,
                completenessLabel: router?.completenessLabel,
                auditState: router?.auditState
            ),
            release: .init(
                hardenedRuntime: gates.hardened,
                notarized: gates.notarized,
                qualityLoopScore: qualityScore
            )
        )
    }

    private static func releaseGates(
        router: RouterAppState?,
        probe: Bool,
        applicationsDirectory: URL,
        fileManager: FileManager
    ) -> (hardened: Bool?, notarized: Bool?) {
        guard probe, router?.installed == true else { return (nil, nil) }
        guard let appURL = resolveInstalledApp(
            router: router,
            applicationsDirectory: applicationsDirectory,
            fileManager: fileManager
        ) else { return (nil, nil) }
        return (
            EvaluationSignalReleaseProbe.hasHardenedRuntime(appURL),
            EvaluationSignalReleaseProbe.isNotarized(appURL)
        )
    }

    private static func resolveInstalledApp(
        router: RouterAppState?,
        applicationsDirectory: URL,
        fileManager: FileManager
    ) -> URL? {
        guard let router else { return nil }
        let names = [router.bundleName, router.displayName, router.processName].compactMap { $0 }
        for name in names {
            let appName = name.hasSuffix(".app") ? name : "\(name).app"
            let url = applicationsDirectory.appending(path: appName, directoryHint: .isDirectory)
            if fileManager.fileExists(atPath: url.path) { return url }
        }
        return nil
    }
}
