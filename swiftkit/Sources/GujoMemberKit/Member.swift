import Foundation

/// 함대 앱이 제각각 갖고 있던 Customer/Member 합집합.
/// 네트워크 없음 — JSON 디코딩과 카드 조립만 한다.
public struct Member: Sendable, Equatable, Hashable, Identifiable, Codable {
    public var id: String
    public var name: String
    public var email: String
    public var locale: String?
    public var createdAt: Date?
    public var tags: [String]

    public init(
        id: String,
        name: String = "",
        email: String,
        locale: String? = nil,
        createdAt: Date? = nil,
        tags: [String] = []
    ) {
        self.id = id
        self.name = name
        self.email = email
        self.locale = locale
        self.createdAt = createdAt
        self.tags = Self.normalizedTags(tags)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case email
        case locale
        case createdAt = "created_at"
        case tags
        case isAdmin = "is_admin"
        case userId = "user_id"
        case userEmail = "user_email"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let userId = MemberJSON.decodeOptionalIdentifier(container, key: CodingKeys.userId),
           container.contains(.userEmail)
        {
            id = userId
        } else {
            id = try MemberJSON.decodeIdentifier(container, key: CodingKeys.id)
        }
        name = (try container.decodeIfPresent(String.self, forKey: .name) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let emailValue = try container.decodeIfPresent(String.self, forKey: .email)
        let userEmail = try container.decodeIfPresent(String.self, forKey: .userEmail)
        email = (emailValue ?? userEmail ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        locale = try container.decodeIfPresent(String.self, forKey: .locale)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        var tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        if try container.decodeIfPresent(Bool.self, forKey: .isAdmin) ?? false {
            tags.append("admin")
        }
        self.tags = Self.normalizedTags(tags)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(email, forKey: .email)
        try container.encodeIfPresent(locale, forKey: .locale)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
        try container.encode(tags, forKey: .tags)
    }

    public var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? email : trimmed
    }

    public static func normalizedTags(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for tag in tags {
            let value = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, !seen.contains(value) else { continue }
            seen.insert(value)
            result.append(value)
        }
        return result
    }
}

/// `GET /api/commerce/staff/customers` 목록 봉투.
public struct StaffCustomerListEnvelope: Sendable, Equatable, Decodable {
    public var data: [Member]
    public var meta: Meta?

    public struct Meta: Sendable, Equatable, Decodable {
        public var count: Int?
        public var limit: Int?
        public var nextCursor: Int?

        enum CodingKeys: String, CodingKey {
            case count, limit
            case nextCursor = "next_cursor"
        }
    }
}
