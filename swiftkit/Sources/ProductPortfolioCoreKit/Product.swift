import Foundation

public enum ProductClassification: String, Codable, CaseIterable, Sendable {
    case productCandidate = "product-candidate"
    case internalTool = "internal-tool"

    public var displayName: String {
        switch self {
        case .productCandidate: "제품 후보"
        case .internalTool: "내부 도구"
        }
    }
}

public enum ProductValidationError: Error, Equatable, LocalizedError, Sendable {
    case invalidSlug(String)
    case invalidReadiness(Int)

    public var errorDescription: String? {
        switch self {
        case let .invalidSlug(slug):
            "slug는 소문자 영숫자와 하이픈만 사용할 수 있습니다: \(slug)"
        case let .invalidReadiness(value):
            "준비도는 0부터 5 사이여야 합니다: \(value)"
        }
    }
}

public struct Product: Codable, Equatable, Identifiable, Sendable {
    public static let readinessRange = 0...5

    public var id: String { slug }
    public var slug: String
    public var nameKo: String
    public var nameEn: String
    public var role: String
    public var classification: ProductClassification
    public var buyerPersona: String
    public var salesAngle: String
    public var categories: [String]
    public var priceIdea: String
    public var readiness: Int
    /// 레거시 경로 목록. generated 슬롯 path 와 동기화 권장.
    public var screenshotPaths: [String]
    /// 프롬프트 선행 비주얼 슬롯 (planned / generated / failed).
    public var visuals: [ProductVisual]

    public struct Names: Equatable, Sendable {
        public var slug: String
        public var nameKo: String
        public var nameEn: String

        public init(slug: String, nameKo: String, nameEn: String) {
            self.slug = slug
            self.nameKo = nameKo
            self.nameEn = nameEn
        }
    }

    public struct Pitch: Equatable, Sendable {
        public var role: String
        public var classification: ProductClassification
        public var buyerPersona: String
        public var salesAngle: String
        public var categories: [String]
        public var priceIdea: String

        public init(
            role: String,
            classification: ProductClassification,
            buyerPersona: String,
            salesAngle: String,
            categories: [String],
            priceIdea: String
        ) {
            self.role = role
            self.classification = classification
            self.buyerPersona = buyerPersona
            self.salesAngle = salesAngle
            self.categories = categories
            self.priceIdea = priceIdea
        }
    }

    public struct Surface: Equatable, Sendable {
        public var readiness: Int
        public var screenshotPaths: [String]
        public var visuals: [ProductVisual]

        public init(
            readiness: Int,
            screenshotPaths: [String],
            visuals: [ProductVisual] = []
        ) {
            self.readiness = readiness
            self.screenshotPaths = screenshotPaths
            self.visuals = visuals
        }
    }

    public init(names: Names, pitch: Pitch, surface: Surface) throws {
        guard Self.isValidSlug(names.slug) else { throw ProductValidationError.invalidSlug(names.slug) }
        guard Self.readinessRange.contains(surface.readiness) else {
            throw ProductValidationError.invalidReadiness(surface.readiness)
        }
        self.slug = names.slug
        self.nameKo = names.nameKo
        self.nameEn = names.nameEn
        self.role = pitch.role
        self.classification = pitch.classification
        self.buyerPersona = pitch.buyerPersona
        self.salesAngle = pitch.salesAngle
        self.categories = pitch.categories
        self.priceIdea = pitch.priceIdea
        self.readiness = surface.readiness
        self.screenshotPaths = surface.screenshotPaths
        self.visuals = surface.visuals
    }

    public static func isValidSlug(_ slug: String) -> Bool {
        guard !slug.isEmpty, slug.first != "-", slug.last != "-" else { return false }
        return slug.allSatisfy { $0.isLowercase || $0.isNumber || $0 == "-" }
    }

    private enum CodingKeys: String, CodingKey {
        case slug, nameKo, nameEn, role, classification, buyerPersona, salesAngle
        case categories, priceIdea, readiness, screenshotPaths, visuals
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            names: Names(
                slug: values.decode(String.self, forKey: .slug),
                nameKo: values.decode(String.self, forKey: .nameKo),
                nameEn: values.decode(String.self, forKey: .nameEn)
            ),
            pitch: Pitch(
                role: values.decode(String.self, forKey: .role),
                classification: values.decode(ProductClassification.self, forKey: .classification),
                buyerPersona: values.decode(String.self, forKey: .buyerPersona),
                salesAngle: values.decode(String.self, forKey: .salesAngle),
                categories: values.decode([String].self, forKey: .categories),
                priceIdea: values.decode(String.self, forKey: .priceIdea)
            ),
            surface: Surface(
                readiness: values.decode(Int.self, forKey: .readiness),
                screenshotPaths: values.decode([String].self, forKey: .screenshotPaths),
                visuals: values.decodeIfPresent([ProductVisual].self, forKey: .visuals) ?? []
            )
        )
    }

    public struct Patch: Equatable, Sendable {
        public struct Names: Equatable, Sendable {
            public var nameKo: String?
            public var nameEn: String?

            public init(nameKo: String? = nil, nameEn: String? = nil) {
                self.nameKo = nameKo
                self.nameEn = nameEn
            }
        }

        public struct Pitch: Equatable, Sendable {
            public var role: String?
            public var classification: ProductClassification?
            public var buyerPersona: String?
            public var salesAngle: String?
            public var categories: [String]?
            public var priceIdea: String?

            public init(
                role: String? = nil,
                classification: ProductClassification? = nil,
                buyerPersona: String? = nil,
                salesAngle: String? = nil,
                categories: [String]? = nil,
                priceIdea: String? = nil
            ) {
                self.role = role
                self.classification = classification
                self.buyerPersona = buyerPersona
                self.salesAngle = salesAngle
                self.categories = categories
                self.priceIdea = priceIdea
            }
        }

        public struct Surface: Equatable, Sendable {
            public var readiness: Int?
            public var screenshotPaths: [String]?
            public var visuals: [ProductVisual]?

            public init(
                readiness: Int? = nil,
                screenshotPaths: [String]? = nil,
                visuals: [ProductVisual]? = nil
            ) {
                self.readiness = readiness
                self.screenshotPaths = screenshotPaths
                self.visuals = visuals
            }
        }

        public var names: Names
        public var pitch: Pitch
        public var surface: Surface

        public init(
            names: Names = Names(),
            pitch: Pitch = Pitch(),
            surface: Surface = Surface()
        ) {
            self.names = names
            self.pitch = pitch
            self.surface = surface
        }
    }

    /// 생성자 인자 폭발을 피하기 위한 부분 갱신.
    public func replacing(_ patch: Patch) throws -> Product {
        try Product(
            names: Names(
                slug: slug,
                nameKo: patch.names.nameKo ?? nameKo,
                nameEn: patch.names.nameEn ?? nameEn
            ),
            pitch: Pitch(
                role: patch.pitch.role ?? role,
                classification: patch.pitch.classification ?? classification,
                buyerPersona: patch.pitch.buyerPersona ?? buyerPersona,
                salesAngle: patch.pitch.salesAngle ?? salesAngle,
                categories: patch.pitch.categories ?? categories,
                priceIdea: patch.pitch.priceIdea ?? priceIdea
            ),
            surface: Surface(
                readiness: patch.surface.readiness ?? readiness,
                screenshotPaths: patch.surface.screenshotPaths ?? screenshotPaths,
                visuals: patch.surface.visuals ?? visuals
            )
        )
    }

    /// generated 슬롯 경로 (비어 있지 않은 path 만).
    public var generatedVisualPaths: [String] {
        visuals.compactMap { slot in
            guard slot.status == .generated,
                  let path = slot.path?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !path.isEmpty
            else { return nil }
            return path
        }
    }

    /// 스크린샷 “채워짐” 판정 — 레거시 경로 또는 generated 슬롯.
    public var hasAnyScreenshotAsset: Bool {
        screenshotPaths.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            || !generatedVisualPaths.isEmpty
    }
}
