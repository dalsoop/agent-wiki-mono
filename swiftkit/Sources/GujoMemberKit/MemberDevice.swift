import Foundation

/// 회원이 활성화한 기기. commerce/staff customers/{id}/devices 응답의 합집합.
public struct MemberDevice: Sendable, Equatable, Hashable, Identifiable, Codable {
    public var id: String
    public var name: String
    public var productId: String?
    public var keyPrefix: String?
    public var revokedAt: Date?
    public var lastUsedAt: Date?
    public var expiresAt: Date?
    public var active: Bool

    public init(
        id: String,
        name: String = "",
        productId: String? = nil,
        keyPrefix: String? = nil,
        revokedAt: Date? = nil,
        lastUsedAt: Date? = nil,
        expiresAt: Date? = nil,
        active: Bool = true
    ) {
        self.id = id
        self.name = name
        self.productId = productId
        self.keyPrefix = keyPrefix
        self.revokedAt = revokedAt
        self.lastUsedAt = lastUsedAt
        self.expiresAt = expiresAt
        self.active = active
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case productId = "product_id"
        case keyPrefix = "key_prefix"
        case revokedAt = "revoked_at"
        case lastUsedAt = "last_used_at"
        case expiresAt = "expires_at"
        case active
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try MemberJSON.decodeIdentifier(container, key: CodingKeys.id)
        name = (try container.decodeIfPresent(String.self, forKey: .name) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        productId = MemberJSON.decodeOptionalIdentifier(container, key: CodingKeys.productId)
        keyPrefix = try container.decodeIfPresent(String.self, forKey: .keyPrefix)
        revokedAt = try container.decodeIfPresent(Date.self, forKey: .revokedAt)
        lastUsedAt = try container.decodeIfPresent(Date.self, forKey: .lastUsedAt)
        expiresAt = try container.decodeIfPresent(Date.self, forKey: .expiresAt)
        if let flag = try container.decodeIfPresent(Bool.self, forKey: .active) {
            active = flag
        } else {
            active = revokedAt == nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(productId, forKey: .productId)
        try container.encodeIfPresent(keyPrefix, forKey: .keyPrefix)
        try container.encodeIfPresent(revokedAt, forKey: .revokedAt)
        try container.encodeIfPresent(lastUsedAt, forKey: .lastUsedAt)
        try container.encodeIfPresent(expiresAt, forKey: .expiresAt)
        try container.encode(active, forKey: .active)
    }

    public var displayName: String {
        if !name.isEmpty { return name }
        if let keyPrefix, !keyPrefix.isEmpty { return keyPrefix }
        return id
    }
}

/// `GET /api/commerce/staff/customers/{id}/devices` 봉투.
public struct StaffDeviceListEnvelope: Sendable, Equatable, Decodable {
    public var data: [MemberDevice]
}
