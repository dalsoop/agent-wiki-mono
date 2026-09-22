import Foundation

/// 디스크 위 앱 패키지에서 관측 가능한 사실만 담는다. 판매 문구는 넣지 않는다.
public struct AppPackageEvidence: Equatable, Sendable {
    public let slug: String
    public let directoryURL: URL
    public let readmeText: String?
    public let hasPackageSwift: Bool
    public let hasTests: Bool
    public let hasSources: Bool

    public init(
        slug: String,
        directoryURL: URL,
        readmeText: String?,
        hasPackageSwift: Bool,
        hasTests: Bool,
        hasSources: Bool
    ) {
        self.slug = slug
        self.directoryURL = directoryURL
        self.readmeText = readmeText
        self.hasPackageSwift = hasPackageSwift
        self.hasTests = hasTests
        self.hasSources = hasSources
    }
}

public enum AppPackageScanner {
    /// `apps/` 아래 Package.swift 가 있는 디렉터리를 스캔한다.
    public static func scan(appsRoot: URL) throws -> [AppPackageEvidence] {
        let fm = FileManager.default
        let entries = try fm.contentsOfDirectory(
            at: appsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        var results: [AppPackageEvidence] = []
        for url in entries {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { continue }
            let packageSwift = url.appendingPathComponent("Package.swift")
            guard fm.fileExists(atPath: packageSwift.path) else { continue }
            let slug = ProductGenerator.slug(fromDirectoryName: url.lastPathComponent)
            guard Product.isValidSlug(slug) else { continue }
            let readme = ["README.md", "Readme.md", "readme.md"]
                .map { url.appendingPathComponent($0) }
                .first { fm.fileExists(atPath: $0.path) }
                .flatMap { try? String(contentsOf: $0, encoding: .utf8) }
            let hasTests = fm.fileExists(atPath: url.appendingPathComponent("Tests").path)
            let hasSources = fm.fileExists(atPath: url.appendingPathComponent("Sources").path)
            results.append(
                AppPackageEvidence(
                    slug: slug,
                    directoryURL: url,
                    readmeText: readme,
                    hasPackageSwift: true,
                    hasTests: hasTests,
                    hasSources: hasSources
                )
            )
        }
        return results.sorted { $0.slug < $1.slug }
    }
}

/// 관측 사실 → Product 객체. 페르소나/판매각/가격은 비워 둔다(추측 금지).
public enum ProductGenerator {
    public static func slug(fromDirectoryName name: String) -> String {
        name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
    }

    public static func displayName(fromSlug slug: String) -> String {
        slug
            .split(separator: "-")
            .map { part -> String in
                guard let first = part.first else { return "" }
                return String(first).uppercased() + part.dropFirst()
            }
            .joined(separator: " ")
    }

    public static func role(fromReadme text: String?) -> String {
        guard let text, !text.isEmpty else { return "" }
        return ProductCopy.plainRole(firstProseLine(in: text))
    }

    public static func classification(forSlug slug: String) -> ProductClassification {
        let internalHints = [
            "stages", "ssot", "orchestrator", "devtools", "e2e", "fleet",
            "hook", "monitor", "bar", "infra", "governor", "router",
        ]
        if internalHints.contains(where: { slug.contains($0) }) {
            return .internalTool
        }
        return .productCandidate
    }

    /// 관측 가능한 완성도 근사치. 판매 문구와 무관.
    public static func readiness(from evidence: AppPackageEvidence) -> Int {
        switch (evidence.hasSources, evidence.hasTests, evidence.hasPackageSwift) {
        case (true, true, true): return 3
        case (true, false, true): return 2
        case (false, _, true): return 1
        default: return 0
        }
    }

    public static func make(from evidence: AppPackageEvidence) throws -> Product {
        let name = displayName(fromSlug: evidence.slug)
        return try Product(
            names: .init(slug: evidence.slug, nameKo: name, nameEn: name),
            pitch: .init(
                role: role(fromReadme: evidence.readmeText),
                classification: classification(forSlug: evidence.slug),
                buyerPersona: "",
                salesAngle: "",
                categories: [],
                priceIdea: ""
            ),
            surface: .init(readiness: readiness(from: evidence), screenshotPaths: [])
        )
    }

    /// README 본문에서 제목·뱃지·코드펜스를 건너뛴 첫 산문 줄.
    public static func firstProseLine(in text: String) -> String {
        var inFence = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                inFence.toggle()
                continue
            }
            if inFence { continue }
            if trimmed.isEmpty { continue }
            if trimmed.hasPrefix("#") { continue }
            if trimmed.hasPrefix("![") { continue }
            if trimmed.hasPrefix("|") { continue }
            if trimmed.hasPrefix("- [") || trimmed.hasPrefix("* [") { continue }
            if trimmed.hasPrefix("[") && trimmed.contains("](") { continue }
            var prose = trimmed
            if prose.hasPrefix("- ") { prose = String(prose.dropFirst(2)) }
            if prose.hasPrefix("* ") { prose = String(prose.dropFirst(2)) }
            if prose.count >= 8 { return prose }
        }
        return ""
    }
}

public struct CatalogSyncResult: Codable, Equatable, Sendable {
    public let created: Int
    public let updated: Int
    public let unchanged: Int
    public let scanned: Int

    public init(created: Int, updated: Int, unchanged: Int, scanned: Int) {
        self.created = created
        self.updated = updated
        self.unchanged = unchanged
        self.scanned = scanned
    }
}

/// apps 루트를 스캔해 없는 제품은 생성, 있는 제품은 빈 role/readiness만 관측값으로 보강.
public enum AppCatalogSync {
    public static func sync(
        appsRoot: URL,
        into store: ProductStore,
        refreshDerived: Bool = true
    ) throws -> CatalogSyncResult {
        let evidence = try AppPackageScanner.scan(appsRoot: appsRoot)
        var created = 0
        var updated = 0
        var unchanged = 0

        for item in evidence {
            let generated = try ProductGenerator.make(from: item)
            if store.contains(slug: item.slug) {
                guard refreshDerived else {
                    unchanged += 1
                    continue
                }
                var current = try store.show(slug: item.slug)
                var changed = false
                if ProductField.role.isMissing(in: current), !ProductCopy.isBlank(generated.role) {
                    current.role = generated.role
                    changed = true
                }
                // readiness 는 관측 근사 — 기존이 0이고 생성값이 더 높을 때만 올림
                if current.readiness == 0, generated.readiness > 0 {
                    current.readiness = generated.readiness
                    changed = true
                }
                if changed {
                    try store.save(
                        try current.replacing(
                            Product.Patch(
                                pitch: .init(role: current.role),
                                surface: .init(readiness: current.readiness)
                            )
                        )
                    )
                    updated += 1
                } else {
                    unchanged += 1
                }
            } else {
                try store.add(generated)
                created += 1
            }
        }
        return CatalogSyncResult(
            created: created,
            updated: updated,
            unchanged: unchanged,
            scanned: evidence.count
        )
    }
}
