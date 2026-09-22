import Foundation

public struct LibraryResponse: Decodable, Sendable {
    public let items: [LibraryItem]
}

public struct LibraryItem: Decodable, Sendable, Identifiable, Hashable {
    public let product: LibraryProduct
    public let bundle: BundleRef?
    public let thumbnail_html: String?
    public let hero_path: String?
    public let hero_alt: String?
    public let access_source: String?
    public var id: Int { product.id }

    enum CodingKeys: String, CodingKey {
        case product, bundle, thumbnail_html, hero_path, hero_alt, access_source
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        product = try c.decode(LibraryProduct.self, forKey: .product)
        bundle = try c.decodeIfPresent(BundleRef.self, forKey: .bundle)
        thumbnail_html = try c.decodeIfPresent(String.self, forKey: .thumbnail_html)
        hero_path = try c.decodeIfPresent(String.self, forKey: .hero_path)
        hero_alt = try c.decodeIfPresent(String.self, forKey: .hero_alt)
        access_source = try c.decodeIfPresent(String.self, forKey: .access_source)
    }

    public init(
        product: LibraryProduct,
        bundle: BundleRef?,
        thumbnail_html: String? = nil,
        hero_path: String? = nil,
        hero_alt: String? = nil,
        access_source: String? = nil
    ) {
        self.product = product
        self.bundle = bundle
        self.thumbnail_html = thumbnail_html
        self.hero_path = hero_path
        self.hero_alt = hero_alt
        self.access_source = access_source
    }
}

/// 플랫폼별 설치 가이드 (예: ko/install/macos.md).
public struct InstallAsset: Codable, Sendable, Hashable, Identifiable {
    public let platform: String
    public let label: String
    public let path: String
    public let download_url: String?
    public var id: String { platform + ":" + path }

    public init(platform: String, label: String, path: String, download_url: String? = nil) {
        self.platform = platform
        self.label = label
        self.path = path
        self.download_url = download_url
    }
}

public struct LibraryProduct: Decodable, Sendable, Hashable {
    public let id: Int
    public let name: String
    public let description: String?
    public let runtime: String?
    public let platforms: [String]
    public let type_label: String?
    public let install_assets: [InstallAsset]

    enum CodingKeys: String, CodingKey {
        case id, name, description, runtime, platforms, type_label, install_assets
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        runtime = try c.decodeIfPresent(String.self, forKey: .runtime)
        platforms = try c.decodeIfPresent([String].self, forKey: .platforms) ?? []
        type_label = try c.decodeIfPresent(String.self, forKey: .type_label)
        install_assets = try c.decodeIfPresent([InstallAsset].self, forKey: .install_assets) ?? []
    }

    public init(
        id: Int,
        name: String,
        description: String? = nil,
        runtime: String? = nil,
        platforms: [String] = [],
        type_label: String? = nil,
        install_assets: [InstallAsset] = []
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.runtime = runtime
        self.platforms = platforms
        self.type_label = type_label
        self.install_assets = install_assets
    }

    /// macOS 설치 가이드 우선, 없으면 첫 install asset.
    public var preferredInstallAsset: InstallAsset? {
        install_assets.first { $0.platform.lowercased().contains("mac") }
            ?? install_assets.first
    }
}

public struct BundleRef: Decodable, Sendable, Hashable {
    public let available: Bool
    public let sha256: String?
    public let size: Int?
    public let download_url: String?
}

public struct GalleryImage: Decodable, Sendable, Equatable {
    public let path: String
    public let caption: String?
    public init(path: String, caption: String? = nil) {
        self.path = path
        self.caption = caption
    }
}

public struct ProductDetailResponse: Decodable, Sendable {
    public let detail_html: String?
    public let ai_prompt_path: String?
    public let usage_path: String?
    public let architecture_path: String?
    public let hero_path: String?
    public let gallery: [GalleryImage]

    public init(
        detail_html: String?,
        ai_prompt_path: String? = nil,
        usage_path: String? = nil,
        architecture_path: String? = nil,
        hero_path: String? = nil,
        gallery: [GalleryImage] = []
    ) {
        self.detail_html = detail_html
        self.ai_prompt_path = ai_prompt_path
        self.usage_path = usage_path
        self.architecture_path = architecture_path
        self.hero_path = hero_path
        self.gallery = gallery
    }

    enum CodingKeys: String, CodingKey {
        case detail_html, ai_prompt_path, usage_path, architecture_path, hero_path, gallery
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        detail_html = try c.decodeIfPresent(String.self, forKey: .detail_html)
        ai_prompt_path = try c.decodeIfPresent(String.self, forKey: .ai_prompt_path)
        usage_path = try c.decodeIfPresent(String.self, forKey: .usage_path)
        architecture_path = try c.decodeIfPresent(String.self, forKey: .architecture_path)
        hero_path = try c.decodeIfPresent(String.self, forKey: .hero_path)
        gallery = try c.decodeIfPresent([GalleryImage].self, forKey: .gallery) ?? []
    }
}

public enum LibraryStatus: Sendable, Equatable {
    case notInstalled
    case installed
    case updateAvailable
}

public struct LibraryRow: Sendable, Identifiable {
    public let item: LibraryItem
    public let status: LibraryStatus
    public var id: Int { item.id }
    public init(item: LibraryItem, status: LibraryStatus) {
        self.item = item
        self.status = status
    }
}

/// Shared product classification predicates — the single source for both the
/// Discover sections (`LibrarySection.make`) and the app's sidebar categories,
/// so the two can't silently drift apart.
public enum ProductTraits {
    public static func isAITool(_ product: LibraryProduct) -> Bool {
        (product.runtime?.localizedCaseInsensitiveContains("agent") ?? false)
            || product.platforms.contains { platform in
                ["codex", "claude", "gemini", "ai"].contains { platform.localizedCaseInsensitiveContains($0) }
            }
    }

    public static func isDeveloperTool(_ product: LibraryProduct) -> Bool {
        let text = ([product.name, product.runtime ?? ""] + product.platforms).joined(separator: " ")
        return ["vscode", "code", "cli", "terminal", "git", "developer"].contains { text.localizedCaseInsensitiveContains($0) }
    }
}

public struct LibrarySection: Sendable, Identifiable {
    /// Stable identity for views to localize against — the `title` strings are
    /// pinned by tests and must not become a UI contract.
    public enum Kind: Sendable {
        case updates, installed, aiTools, developer, more
    }

    public let kind: Kind
    public let title: String
    public let rows: [LibraryRow]
    public var id: String { title }

    public static func make(from rows: [LibraryRow]) -> [LibrarySection] {
        var used = Set<Int>()
        var sections: [LibrarySection] = []

        func take(_ kind: Kind, _ title: String, where predicate: (LibraryRow) -> Bool) {
            let selected = rows.filter { !used.contains($0.id) && predicate($0) }
            guard !selected.isEmpty else { return }
            selected.forEach { used.insert($0.id) }
            sections.append(LibrarySection(kind: kind, title: title, rows: selected))
        }

        take(.updates, "Updates") { $0.status == .updateAvailable }
        take(.installed, "Installed") { $0.status == .installed }
        take(.aiTools, "AI Tools") { ProductTraits.isAITool($0.item.product) }
        take(.developer, "Developer") { ProductTraits.isDeveloperTool($0.item.product) }
        take(.more, "More Apps") { _ in true }

        return sections
    }
}

public struct InstalledProduct: Codable, Sendable {
    public let productId: Int
    public let name: String
    public let bundleSha256: String?
    public let installedAt: Date
    public let sizeBytes: Int
    public init(productId: Int, name: String, bundleSha256: String?, installedAt: Date, sizeBytes: Int) {
        self.productId = productId
        self.name = name
        self.bundleSha256 = bundleSha256
        self.installedAt = installedAt
        self.sizeBytes = sizeBytes
    }
}
