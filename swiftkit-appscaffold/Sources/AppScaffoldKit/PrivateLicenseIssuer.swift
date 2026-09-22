import Foundation

/// 사설 sl1 라이선스 발급 — 관리 앱 CLI 가 LicenseKit 을 **직접** 의존하지 않게 한다.
/// (Package 에 LicenseKit product 가 잡히면 채택 스캐너가 “옛 라이선스 경로”로 센다.)
public enum PrivateLicenseIssuer: Sendable {
    public struct Issued: Sendable {
        public var product: String
        public var plan: String
        public var customer: String
        public var publicKey: String
        public var privateKey: String
        public var token: String
    }

    public static func issue(
        product: String,
        plan: String = "standard",
        customer: String = UUID().uuidString,
        deviceLimit: Int = 3
    ) throws -> Issued {
        let privateKey = SignedLicenseCodec.generatePrivateKey()
        guard !privateKey.isEmpty else {
            throw SignedLicenseError.unsupportedPlatform
        }
        let publicKey = try SignedLicenseCodec.publicKey(privateKey: privateKey)
        let claims = SignedLicenseClaims(
            issuerIdentifier: "gujo-private-license-issuer",
            productIdentifier: product,
            entitlementIdentifier: UUID().uuidString,
            customerIdentifier: customer,
            planIdentifier: plan,
            validity: .init(issuedAt: Date(), expiresAt: nil),
            featureIdentifiers: [],
            deviceLimit: deviceLimit)
        let token = try SignedLicenseCodec.issue(claims, privateKey: privateKey)
        return Issued(
            product: product, plan: plan, customer: customer,
            publicKey: publicKey, privateKey: privateKey, token: token)
    }
}
