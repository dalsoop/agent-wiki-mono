import Foundation

/// 기기 단위 SSO로 받은 소유 제품 권한 정보.
@available(*, deprecated, message: "EntitlementKit 을 쓴다")
public struct DeviceEntitlement: Codable, Sendable, Equatable, Identifiable {
    public var id: String { productID }

    public let productID: String
    public let productName: String
    public let bundleIdentifier: String
    public let licenseKey: String
    public let activatedAt: Date
    public let expiresAt: Date?
    public let plan: String

    public init(
        productID: String,
        productName: String,
        bundleIdentifier: String,
        licenseKey: String,
        activatedAt: Date,
        expiresAt: Date?,
        plan: String
    ) {
        self.productID = productID
        self.productName = productName
        self.bundleIdentifier = bundleIdentifier
        self.licenseKey = licenseKey
        self.activatedAt = activatedAt
        self.expiresAt = expiresAt
        self.plan = plan
    }

    enum CodingKeys: String, CodingKey {
        case productID = "product_id"
        case productName = "product_name"
        case bundleIdentifier = "bundle_identifier"
        case licenseKey = "license_key"
        case activatedAt = "activated_at"
        case expiresAt = "expires_at"
        case plan
    }
}
