import EndpointRouterKit
import Foundation
@testable import GujoCoreKit
import Testing

@Suite struct GujoManagedTokenTests {
    // 테스트용 Curve25519 키쌍
    // priv: +UFcGoC+42zJjLwv1wdYhKsAs3hZCdUuLqpPj7qVipY=
    // pub:  dyOm/RdedofBuDf38c1unku3/OE24/h6zrSzx4w5BPA=
    static let testPrivateKey = "+UFcGoC+42zJjLwv1wdYhKsAs3hZCdUuLqpPj7qVipY="
    static let testPublicKey = "dyOm_RdedofBuDf38c1unku3_OE24_h6zrSzx4w5BPA"

    // MARK: - 1. 토큰 서명 및 검증 테스트

    @Test func tokenSigningAndVerificationSucceeds() throws {
        let bundleID = "net.ranode.sample-app"
        let issuedAt = Date()
        let token = try SignedEntitlementToken.sign(
            bundleID: bundleID,
            status: .available,
            issuedAt: issuedAt,
            privateKey: Self.testPrivateKey
        )

        #expect(!token.signature.isEmpty)
        #expect(token.bundleID == bundleID)
        #expect(token.status == .available)
        #expect(token.verifySignature(publicKey: Self.testPublicKey))
        #expect(token.isValid(at: issuedAt, expectedBundleID: bundleID, publicKey: Self.testPublicKey))
        #expect(token.effectiveStatus(at: issuedAt, expectedBundleID: bundleID, publicKey: Self.testPublicKey) == .available)
    }

    @Test func tokenSignatureFailsWithTamperedData() throws {
        let bundleID = "net.ranode.sample-app"
        let issuedAt = Date()
        var token = try SignedEntitlementToken.sign(
            bundleID: bundleID,
            status: .available,
            issuedAt: issuedAt,
            privateKey: Self.testPrivateKey
        )

        // 페이로드 위조 시도 (다른 앱 bundle ID로 변경)
        token.bundleID = "net.ranode.attacker-app"
        #expect(!token.verifySignature(publicKey: Self.testPublicKey))
        #expect(!token.isValid(at: issuedAt, expectedBundleID: "net.ranode.attacker-app", publicKey: Self.testPublicKey))
        #expect(token.effectiveStatus(at: issuedAt, expectedBundleID: "net.ranode.attacker-app", publicKey: Self.testPublicKey) == nil)
    }

    @Test func tokenValidationFailsOnBundleIDMismatch() throws {
        let issuedAt = Date()
        let token = try SignedEntitlementToken.sign(
            bundleID: "net.ranode.sample-app",
            status: .available,
            issuedAt: issuedAt,
            privateKey: Self.testPrivateKey
        )

        // 서명 자체는 유효하지만 요청한 bundleID와 불일치
        #expect(!token.isValid(at: issuedAt, expectedBundleID: "net.ranode.different-app", publicKey: Self.testPublicKey))
        #expect(token.effectiveStatus(at: issuedAt, expectedBundleID: "net.ranode.different-app", publicKey: Self.testPublicKey) == nil)
    }

    // MARK: - 2. TTL 30일 만료 테스트

    @Test func tokenTTLThirtyDaysBehavior() throws {
        let bundleID = "net.ranode.sample-app"
        let issuedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let token = try SignedEntitlementToken.sign(
            bundleID: bundleID,
            status: .available,
            issuedAt: issuedAt,
            privateKey: Self.testPrivateKey
        )

        // 29일 경과 시점: 유효 (만료 전)
        let dateDay29 = issuedAt.addingTimeInterval(29 * 24 * 60 * 60)
        #expect(!token.isExpired(at: dateDay29))
        #expect(token.isValid(at: dateDay29, expectedBundleID: bundleID, publicKey: Self.testPublicKey))
        #expect(token.effectiveStatus(at: dateDay29, expectedBundleID: bundleID, publicKey: Self.testPublicKey) == .available)

        // 30일 1초 경과 시점: 만료 (TTL 초과)
        let dateDay30Plus = issuedAt.addingTimeInterval((30 * 24 * 60 * 60) + 1)
        #expect(token.isExpired(at: dateDay30Plus))
        #expect(!token.isValid(at: dateDay30Plus, expectedBundleID: bundleID, publicKey: Self.testPublicKey))
        #expect(token.effectiveStatus(at: dateDay30Plus, expectedBundleID: bundleID, publicKey: Self.testPublicKey) == nil)
    }

    @Test func customExpiresAtTakesPrecedenceOverDefaultTTL() throws {
        let bundleID = "net.ranode.sample-app"
        let issuedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let customExpiresAt = issuedAt.addingTimeInterval(7 * 24 * 60 * 60) // 7일 만료
        let token = try SignedEntitlementToken.sign(
            bundleID: bundleID,
            status: .available,
            issuedAt: issuedAt,
            expiresAt: customExpiresAt,
            privateKey: Self.testPrivateKey
        )

        // 6일 경과: 유효
        let dateDay6 = issuedAt.addingTimeInterval(6 * 24 * 60 * 60)
        #expect(!token.isExpired(at: dateDay6))
        #expect(token.isValid(at: dateDay6, expectedBundleID: bundleID, publicKey: Self.testPublicKey))

        // 8일 경과: 만료
        let dateDay8 = issuedAt.addingTimeInterval(8 * 24 * 60 * 60)
        #expect(token.isExpired(at: dateDay8))
        #expect(!token.isValid(at: dateDay8, expectedBundleID: bundleID, publicKey: Self.testPublicKey))
    }

    // MARK: - 3. 철회 및 24시간 Grace Period 테스트

    @Test func tokenRevocationGracePeriodBehavior() throws {
        let bundleID = "net.ranode.sample-app"
        let issuedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let revokedAt = issuedAt.addingTimeInterval(10 * 24 * 60 * 60) // 발급 10일 후 철회

        let token = try SignedEntitlementToken.sign(
            bundleID: bundleID,
            status: .available,
            issuedAt: issuedAt,
            revokedAt: revokedAt,
            privateKey: Self.testPrivateKey
        )

        #expect(token.isRevoked)

        // 철회 시점 1시간 후: 24시간 grace period 이내이므로 유효하게 취급
        let withinGrace = revokedAt.addingTimeInterval(1 * 60 * 60)
        #expect(token.isWithinRevocationGracePeriod(at: withinGrace))
        #expect(!token.isRevocationGracePeriodExpired(at: withinGrace))
        #expect(token.isValid(at: withinGrace, expectedBundleID: bundleID, publicKey: Self.testPublicKey))
        #expect(token.effectiveStatus(at: withinGrace, expectedBundleID: bundleID, publicKey: Self.testPublicKey) == .available)

        // 철회 시점 23시간 50분 후: 여전히 grace period 이내
        let nearGraceEnd = revokedAt.addingTimeInterval(23 * 3600 + 50 * 60)
        #expect(token.isWithinRevocationGracePeriod(at: nearGraceEnd))
        #expect(!token.isRevocationGracePeriodExpired(at: nearGraceEnd))
        #expect(token.isValid(at: nearGraceEnd, expectedBundleID: bundleID, publicKey: Self.testPublicKey))

        // 철회 시점 24시간 1초 후: grace period 만료로 무효화
        let graceExpired = revokedAt.addingTimeInterval(24 * 60 * 60 + 1)
        #expect(!token.isWithinRevocationGracePeriod(at: graceExpired))
        #expect(token.isRevocationGracePeriodExpired(at: graceExpired))
        #expect(!token.isValid(at: graceExpired, expectedBundleID: bundleID, publicKey: Self.testPublicKey))
        #expect(token.effectiveStatus(at: graceExpired, expectedBundleID: bundleID, publicKey: Self.testPublicKey) == nil)
    }

    // MARK: - 4. EndpointRouterKit 원장 조회 연동 테스트

    @Test func downloadURLResolvesViaEndpointRouterKit() {
        let downloadsURL = EndpointRouter.downloadsURL()
        #expect(downloadsURL != nil)
        if let url = downloadsURL {
            #expect(!url.absoluteString.isEmpty)
            #expect(url.absoluteString.contains("downloads"))
            #expect(url.scheme == "https" || url.scheme == "http")
        }
    }

    // MARK: - 5. SignedEntitlementToken 상태 판정 테스트

    @Test func tokenEffectiveStatusWithValidity() throws {
        let bundleID = "net.ranode.sample-lastknown"
        let issuedAt = Date()
        let token = try SignedEntitlementToken.sign(
            bundleID: bundleID,
            status: .available,
            issuedAt: issuedAt,
            privateKey: Self.testPrivateKey
        )

        // 유효 기간 내에는 available 반환
        let status = token.effectiveStatus(at: issuedAt, expectedBundleID: bundleID, publicKey: Self.testPublicKey)
        #expect(status == .available)

        // TTL 30일 초과 시점에는 nil 반환
        let expiredDate = issuedAt.addingTimeInterval(31 * 24 * 60 * 60)
        let expiredStatus = token.effectiveStatus(at: expiredDate, expectedBundleID: bundleID, publicKey: Self.testPublicKey)
        #expect(expiredStatus == nil)
    }

    @Test func serializationRoundTrip() throws {
        let bundleID = "net.ranode.sample-serialize"
        let issuedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let token = try SignedEntitlementToken.sign(
            bundleID: bundleID,
            status: .available,
            issuedAt: issuedAt,
            privateKey: Self.testPrivateKey
        )

        let encoded = try token.encodeToken()
        let parsed = try SignedEntitlementToken.parse(encoded)
        #expect(parsed == token)
        #expect(parsed.isValid(at: issuedAt, expectedBundleID: bundleID, publicKey: Self.testPublicKey))
    }
}
