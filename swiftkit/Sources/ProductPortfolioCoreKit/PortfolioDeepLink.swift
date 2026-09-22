import Foundation

/// 포트폴리오 허브 앱 간 이동 대상.
/// URL: `product-portfolio://{destination}/{slug}`
public enum PortfolioHubDestination: String, CaseIterable, Sendable, Codable {
    case evaluation
    case feedback
    case backlog

    /// 설치본 앱의 CFBundleIdentifier.
    public var bundleIdentifier: String {
        switch self {
        case .evaluation: "net.ranode.productevaluationstudio"
        case .feedback: "net.ranode.customer-feedback-studio"
        case .backlog: "net.ranode.feature-backlog-studio"
        }
    }

    /// `/Applications` 및 배포 이름 후보.
    public var applicationCandidates: [String] {
        switch self {
        case .evaluation:
            ["ProductEvaluationStudio.app", "Product Evaluation Studio.app"]
        case .feedback:
            ["customer-feedback-studio.app", "CustomerFeedbackStudio.app"]
        case .backlog:
            ["feature-backlog-studio.app", "FeatureBacklogStudio.app"]
        }
    }

    public var displayName: String {
        switch self {
        case .evaluation: "평가"
        case .feedback: "피드백"
        case .backlog: "백로그"
        }
    }
}

/// `product-portfolio://evaluation/{slug}` 형태의 딥링크.
public struct PortfolioDeepLink: Equatable, Sendable, Hashable {
    public static let scheme = "product-portfolio"

    public let destination: PortfolioHubDestination
    public let slug: String

    public init(destination: PortfolioHubDestination, slug: String) throws {
        let normalized = Self.normalizeSlug(slug)
        guard !normalized.isEmpty else {
            throw PortfolioDeepLinkError.emptySlug
        }
        guard Self.isValidSlug(normalized) else {
            throw PortfolioDeepLinkError.invalidSlug(slug)
        }
        self.destination = destination
        self.slug = normalized
    }

    /// evaluation 앱 등: 이 목적지의 URL 이면 slug, 아니면 nil.
    public static func productSlug(from url: URL, destination: PortfolioHubDestination = .evaluation) -> String? {
        guard let link = PortfolioDeepLink(url: url), link.destination == destination else {
            return nil
        }
        return link.slug
    }

    public init?(url: URL) {
        guard let scheme = url.scheme?.lowercased(), scheme == Self.scheme else {
            return nil
        }
        guard let host = url.host?.lowercased(),
              let destination = PortfolioHubDestination(rawValue: host) else {
            return nil
        }

        let pathSlug: String
        if url.path.isEmpty || url.path == "/" {
            // product-portfolio://evaluation?slug=foo 도 허용
            if let querySlug = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "slug" })?
                .value {
                pathSlug = querySlug
            } else {
                return nil
            }
        } else {
            pathSlug = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }

        guard let link = try? PortfolioDeepLink(destination: destination, slug: pathSlug) else {
            return nil
        }
        self = link
    }

    public var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = destination.rawValue
        components.path = "/\(slug)"
        // path 가 항상 설정되도록 force-unwrap 대신 fallback
        return components.url ?? URL(string: "\(Self.scheme)://\(destination.rawValue)/\(slug)")!
    }

    public static func normalizeSlug(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// showcase Product.slug 와 같은 보수적 규칙: 소문자, 숫자, `-`.
    public static func isValidSlug(_ slug: String) -> Bool {
        guard !slug.isEmpty, slug.count <= 120 else { return false }
        return slug.unicodeScalars.allSatisfy { scalar in
            (scalar.value >= 0x30 && scalar.value <= 0x39) // 0-9
                || (scalar.value >= 0x61 && scalar.value <= 0x7A) // a-z
                || scalar == "-"
        }
    }
}

public enum PortfolioDeepLinkError: Error, Equatable, LocalizedError, Sendable {
    case emptySlug
    case invalidSlug(String)

    public var errorDescription: String? {
        switch self {
        case .emptySlug: "제품 slug 가 비어 있습니다."
        case let .invalidSlug(value): "올바르지 않은 제품 slug 입니다: \(value)"
        }
    }
}
