import Foundation
import Testing
@testable import AppScaffoldKit

// env 주입 테스트가 있어 병렬이면 isConfigured 가 오염된다.
@Suite(.serialized)
struct EntitlementTests {
    @Test func channelFromAppStorePrimary() {
        #expect(EntitlementChannelKind(rawValue: "appstore") == .appstore)
        #expect(EntitlementChannelKind(rawValue: "direct") == .direct)
        #expect(EntitlementChannelKind(rawValue: "play") == .play)
        #expect(EntitlementChannelKind(rawValue: "private") == .privateStore)
    }

    @Test func appStoreChannelWithEmptyProductsIsAvailable() async {
        let s = await Entitlement.status(channel: .appstore, productIDs: [])
        #expect(s == .available)
    }

    @Test func appStoreCatalogWithoutEnforceIsAvailable() async {
        // product IDs 만 있고 enforce 없으면 벽돌 없음
        let s = await AppStoreManaged.status(productIDs: ["net.example.pro"])
        #expect(s == .available)
        #expect(AppStoreManaged.isEnforced() == false)
    }

    @Test func playScaffoldAndTokenEnforce() async {
        #expect(await Entitlement.status(channel: .play) == .available)
        PlayBillingManaged.clearPurchases()
        // enforce off → product ids only still open
        #expect(await PlayBillingManaged.hasEntitlement(productIDs: ["sku.a"]) == true)
        // record + simulate enforce via env is process-wide; unit-test token store only
        PlayBillingManaged.recordPurchase(productID: "sku.a", token: "tok-1")
        #expect(PlayBillingManaged.recordedProductIDs().contains("sku.a"))
        PlayBillingManaged.clearPurchases()
        #expect(PlayBillingManaged.recordedProductIDs().isEmpty)
    }

    @Test func privateLicenseVerifyRealToken() async throws {
        let privateKey = SignedLicenseCodec.generatePrivateKey()
        #expect(!privateKey.isEmpty)
        let publicKey = try SignedLicenseCodec.publicKey(privateKey: privateKey)
        let claims = SignedLicenseClaims(
            issuerIdentifier: "test-issuer",
            productIdentifier: "net.example.private-app",
            entitlementIdentifier: "ent-1",
            customerIdentifier: "cust-1",
            planIdentifier: "standard",
            validity: .init(issuedAt: Date(), expiresAt: nil),
            featureIdentifiers: [],
            deviceLimit: 2
        )
        let token = try SignedLicenseCodec.issue(claims, privateKey: privateKey)
        // inject via env for loadToken
        setenv("GUJO_PRIVATE_LICENSE_PUBLIC_KEY", publicKey, 1)
        setenv("GUJO_SIGNED_LICENSE", token, 1)
        defer {
            unsetenv("GUJO_PRIVATE_LICENSE_PUBLIC_KEY")
            unsetenv("GUJO_SIGNED_LICENSE")
        }
        // product id must match — override via PrivateLicenseProductID not on main bundle;
        // verify path with codec directly proves wiring; status uses main bundle id.
        let ok = try SignedLicenseCodec.verify(
            token, publicKey: publicKey, expectedProductIdentifier: "net.example.private-app"
        )
        #expect(ok.productIdentifier == "net.example.private-app")
        #expect(PrivateLicenseManaged.isConfigured() == true)
        // wrong product → not entitled path via codec
        do {
            _ = try SignedLicenseCodec.verify(
                token, publicKey: publicKey, expectedProductIdentifier: "other.product"
            )
            Issue.record("expected wrongProduct")
        } catch let err as SignedLicenseError {
            #expect(err == .wrongProduct)
        }
    }

    @Test func privateUnconfiguredFailOpen() async {
        unsetenv("GUJO_PRIVATE_LICENSE_PUBLIC_KEY")
        unsetenv("GUJO_SIGNED_LICENSE")
        #expect(PrivateLicenseManaged.isConfigured() == false)
        #expect(await PrivateLicenseManaged.status() == .available)
    }

    @Test func playProductIDsFromEmptyBundle() {
        #expect(PlayBillingManaged.productIDs(from: .main).isEmpty)
    }
}
