import Foundation

/// 리스팅에 올린 스크린샷/아이콘 한 장.
public struct StoreListingImage: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    /// 디스크 절대 경로 (보통 listings/<slug>/images/…).
    public var path: String
    /// nil = Mac·iPhone 공용. mac / ios 지정 시 해당 플랫폼 미리보기 우선.
    public var platform: String?
    /// screenshot | icon
    public var kind: String
    public var originalName: String

    public init(
        id: String = UUID().uuidString.lowercased(),
        path: String,
        platform: String? = nil,
        kind: String = "screenshot",
        originalName: String = ""
    ) {
        self.id = id
        self.path = path
        self.platform = platform
        self.kind = kind
        self.originalName = originalName
    }

    public var platformValue: StoreListingPlatform? {
        guard let platform else { return nil }
        return StoreListingPlatform(rawValue: platform)
    }
}

/// 앱스토어 리스팅 미리보기용 판매 카피 + 업로드 이미지 문서.
/// Product 메타와 분리 — 스토어 문구·샷을 버전 관리한다.
public struct StoreListing: Codable, Equatable, Identifiable, Sendable {
    public var id: String { "\(slug)@\(versionId)" }

    public var slug: String
    /// `current` 또는 `yyyyMMdd'T'HHmmss'Z'` 스냅샷 id.
    public var versionId: String
    public var savedAt: String
    public var note: String

    public var name: String
    public var subtitle: String
    public var description: String
    public var promotionalText: String
    public var whatsNew: String
    public var keywords: String
    public var category: String
    public var priceLabel: String
    /// 받기 / 구매 / 구독 등 CTA 라벨.
    public var primaryCTA: String
    /// 리스팅에 업로드한 이미지 (미리보기 우선순위 최상위).
    public var images: [StoreListingImage]

    public struct Identity: Equatable, Sendable {
        public var slug: String
        public var versionId: String
        public var savedAt: String
        public var note: String

        public init(
            slug: String,
            versionId: String = "current",
            savedAt: String = StoreListing.nowISO8601(),
            note: String = ""
        ) {
            self.slug = slug
            self.versionId = versionId
            self.savedAt = savedAt
            self.note = note
        }
    }

    public struct Copy: Equatable, Sendable {
        public var name: String
        public var subtitle: String
        public var description: String
        public var promotionalText: String
        public var whatsNew: String

        public init(
            name: String,
            subtitle: String = "",
            description: String = "",
            promotionalText: String = "",
            whatsNew: String = ""
        ) {
            self.name = name
            self.subtitle = subtitle
            self.description = description
            self.promotionalText = promotionalText
            self.whatsNew = whatsNew
        }
    }

    public struct Merch: Equatable, Sendable {
        public var keywords: String
        public var category: String
        public var priceLabel: String
        public var primaryCTA: String
        public var images: [StoreListingImage]

        public init(
            keywords: String = "",
            category: String = "",
            priceLabel: String = "",
            primaryCTA: String = "구매",
            images: [StoreListingImage] = []
        ) {
            self.keywords = keywords
            self.category = category
            self.priceLabel = priceLabel
            self.primaryCTA = primaryCTA
            self.images = images
        }
    }

    public init(identity: Identity, copy: Copy, merch: Merch = Merch()) {
        self.slug = identity.slug
        self.versionId = identity.versionId
        self.savedAt = identity.savedAt
        self.note = identity.note
        self.name = copy.name
        self.subtitle = copy.subtitle
        self.description = copy.description
        self.promotionalText = copy.promotionalText
        self.whatsNew = copy.whatsNew
        self.keywords = merch.keywords
        self.category = merch.category
        self.priceLabel = merch.priceLabel
        self.primaryCTA = merch.primaryCTA
        self.images = merch.images
    }

    private enum CodingKeys: String, CodingKey {
        case slug, versionId, savedAt, note
        case name, subtitle, description, promotionalText, whatsNew
        case keywords, category, priceLabel, primaryCTA, images
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        slug = try c.decode(String.self, forKey: .slug)
        versionId = try c.decodeIfPresent(String.self, forKey: .versionId) ?? "current"
        savedAt = try c.decodeIfPresent(String.self, forKey: .savedAt) ?? StoreListing.nowISO8601()
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        name = try c.decode(String.self, forKey: .name)
        subtitle = try c.decodeIfPresent(String.self, forKey: .subtitle) ?? ""
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        promotionalText = try c.decodeIfPresent(String.self, forKey: .promotionalText) ?? ""
        whatsNew = try c.decodeIfPresent(String.self, forKey: .whatsNew) ?? ""
        keywords = try c.decodeIfPresent(String.self, forKey: .keywords) ?? ""
        category = try c.decodeIfPresent(String.self, forKey: .category) ?? ""
        priceLabel = try c.decodeIfPresent(String.self, forKey: .priceLabel) ?? ""
        primaryCTA = try c.decodeIfPresent(String.self, forKey: .primaryCTA) ?? "구매"
        images = try c.decodeIfPresent([StoreListingImage].self, forKey: .images) ?? []
    }

    /// 스크린샷 경로만 (아이콘 제외). platform 필터 시 공용+해당 플랫폼.
    public func screenshotPaths(for platform: StoreListingPlatform? = nil) -> [String] {
        images
            .filter { $0.kind != "icon" }
            .filter { image in
                guard let platform else { return true }
                guard let raw = image.platform, let tagged = StoreListingPlatform(rawValue: raw) else {
                    return true
                }
                return tagged == platform
            }
            .map(\.path)
    }

    public var iconPath: String? {
        images.first(where: { $0.kind == "icon" })?.path
    }

    /// Product + 랜딩 문구로 초안 리스팅을 만든다 (디스크 저장 전).
    public static func seeded(
        from product: Product,
        landingMarkdown: String? = nil
    ) -> StoreListing {
        let name = product.nameKo.isEmpty ? product.slug : product.nameKo
        let subtitle = product.salesAngle.isEmpty ? product.role : product.salesAngle
        let description: String = {
            if let landing = landingMarkdown {
                let lines = landing
                    .components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter {
                        !$0.isEmpty
                            && !$0.hasPrefix("#")
                            && !$0.hasPrefix("-")
                            && !$0.hasPrefix("_")
                            && !$0.hasPrefix("[")
                    }
                if let first = lines.first { return first }
            }
            if !product.salesAngle.isEmpty { return product.salesAngle }
            return product.role
        }()
        let cta: String = {
            let price = product.priceIdea.lowercased()
            if price.contains("무료") || price.contains("free") { return "받기" }
            if price.contains("구독") || price.contains("월") { return "구독" }
            return "구매"
        }()
        return StoreListing(
            identity: .init(slug: product.slug, versionId: "current", note: "seeded-from-product"),
            copy: .init(
                name: name,
                subtitle: subtitle,
                description: description,
                promotionalText: product.role
            ),
            merch: .init(
                keywords: product.categories.joined(separator: ", "),
                category: product.categories.first ?? "",
                priceLabel: product.priceIdea,
                primaryCTA: cta
            )
        )
    }

    public static func nowISO8601() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    public static func makeVersionId(at date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss"
        let stamp = formatter.string(from: date)
        let ms = Int((date.timeIntervalSince1970 * 1000).truncatingRemainder(dividingBy: 1000))
        let suffix = String(UUID().uuidString.prefix(4)).lowercased()
        return String(format: "%@%03dZ-%@", stamp, ms, suffix)
    }
}

/// 미리보기 대상 플랫폼 (표시 모드 — 리스팅 본문은 공유).
public enum StoreListingPlatform: String, Codable, CaseIterable, Sendable {
    case mac
    case ios

    public var displayName: String {
        switch self {
        case .mac: "Mac"
        case .ios: "iPhone"
        }
    }

    public var storeChromeTitle: String {
        switch self {
        case .mac: "Mac App Store"
        case .ios: "App Store"
        }
    }
}

/// 버전 목록 한 줄 (current 제외, 스냅샷만).
public struct StoreListingVersionInfo: Codable, Equatable, Identifiable, Sendable {
    public var id: String { versionId }
    public var versionId: String
    public var savedAt: String
    public var note: String
    public var name: String

    public init(versionId: String, savedAt: String, note: String, name: String) {
        self.versionId = versionId
        self.savedAt = savedAt
        self.note = note
        self.name = name
    }

    public init(from listing: StoreListing) {
        self.versionId = listing.versionId
        self.savedAt = listing.savedAt
        self.note = listing.note
        self.name = listing.name
    }
}
