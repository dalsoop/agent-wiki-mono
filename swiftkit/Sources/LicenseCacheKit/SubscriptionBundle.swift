import Foundation

/// 여러 제품을 하나의 구독으로 묶는 번들 모델.
///
/// Gujo Store API가 `/api/bundles`로 제공하는 묶음 구독 단위다.
/// `productIDs`에 포함된 제품은 개별 라이선스 없이도 기능을 사용할 수 있다.
@available(*, deprecated, message: "EntitlementKit 을 쓴다")
public struct SubscriptionBundle: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    /// 사용자에게 표시할 번들 이름. 예: "전체팩", "개발자팩", "크리에이터팩"
    public let name: String
    public let description: String
    /// 이 번들에 포함된 Gujo Store 제품 ID 목록.
    public let productIDs: [Int]
    public let priceMonthly: Decimal?
    public let priceYearly: Decimal?
    /// 현재 사용자가 이 번들을 구독 중인지.
    public let isActive: Bool
    /// 구독 만료 예정 시각. nil이면 무기한이거나 비활성.
    public let expiresAt: Date?

    public init(
        id: String,
        name: String,
        description: String,
        productIDs: [Int],
        priceMonthly: Decimal?,
        priceYearly: Decimal?,
        isActive: Bool,
        expiresAt: Date?
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.productIDs = productIDs
        self.priceMonthly = priceMonthly
        self.priceYearly = priceYearly
        self.isActive = isActive
        self.expiresAt = expiresAt
    }

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case productIDs = "product_ids"
        case priceMonthly = "price_monthly"
        case priceYearly = "price_yearly"
        case isActive = "is_active"
        case expiresAt = "expires_at"
    }
}
