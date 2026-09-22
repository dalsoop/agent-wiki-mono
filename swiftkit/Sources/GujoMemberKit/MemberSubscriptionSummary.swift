import Foundation

/// 고객 카드에 올릴 구독 한 줄 요약. 상세 원장은 판매 앱이 소유한다.
public struct MemberSubscriptionSummary: Sendable, Equatable, Hashable, Codable {
    public var id: String
    public var status: String
    public var productName: String?
    public var startsAt: Date?
    public var endsAt: Date?
    public var cancelAtPeriodEnd: Bool

    public init(
        id: String,
        status: String,
        productName: String? = nil,
        startsAt: Date? = nil,
        endsAt: Date? = nil,
        cancelAtPeriodEnd: Bool = false
    ) {
        self.id = id
        self.status = status
        self.productName = productName
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.cancelAtPeriodEnd = cancelAtPeriodEnd
    }

    enum CodingKeys: String, CodingKey {
        case id
        case status
        case productName = "product_name"
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case cancelAtPeriodEnd = "cancel_at_period_end"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try MemberJSON.decodeIdentifier(container, key: CodingKeys.id)
        status = (try container.decodeIfPresent(String.self, forKey: .status) ?? "none")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        productName = try container.decodeIfPresent(String.self, forKey: .productName)
        startsAt = try container.decodeIfPresent(Date.self, forKey: .startsAt)
        endsAt = try container.decodeIfPresent(Date.self, forKey: .endsAt)
        cancelAtPeriodEnd = try container.decodeIfPresent(Bool.self, forKey: .cancelAtPeriodEnd) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(productName, forKey: .productName)
        try container.encodeIfPresent(startsAt, forKey: .startsAt)
        try container.encodeIfPresent(endsAt, forKey: .endsAt)
        try container.encode(cancelAtPeriodEnd, forKey: .cancelAtPeriodEnd)
    }

    public var isActive: Bool {
        status == "active" || status == "trial"
    }
}
