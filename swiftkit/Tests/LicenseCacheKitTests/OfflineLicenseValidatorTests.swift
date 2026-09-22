import Foundation
import CryptoKit
import Testing
@testable import LicenseCacheKit

@Suite("OfflineLicenseValidator Tests")
struct OfflineLicenseValidatorTests {

    @Test("정상 서명된 라이선스 파일 검증 성공")
    func testValidLicenseVerification() throws {
        let (privateKey, publicKey) = OfflineLicenseValidator.generateKeyPair()
        let validator = OfflineLicenseValidator(publicKey: publicKey)

        let issued = try OfflineLicenseValidator.sign(
            bundleId: "kr.gujo.test-app",
            plan: "pro",
            customer: "user-12345",
            issuedAt: Date(timeIntervalSince1970: 1700000000),
            expiresAt: nil,
            privateKey: privateKey
        )

        let result = try validator.validate(jsonString: issued.json, expectedBundleId: "kr.gujo.test-app")
        #expect(result.bundleId == "kr.gujo.test-app")
        #expect(result.plan == "pro")
        #expect(result.customer == "user-12345")
    }

    @Test("bundleId 불일치 시 거부")
    func testBundleMismatch() throws {
        let (privateKey, publicKey) = OfflineLicenseValidator.generateKeyPair()
        let validator = OfflineLicenseValidator(publicKey: publicKey)

        let issued = try OfflineLicenseValidator.sign(
            bundleId: "kr.gujo.other-app",
            privateKey: privateKey
        )

        #expect(throws: OfflineLicenseError.self) {
            try validator.validate(jsonString: issued.json, expectedBundleId: "kr.gujo.test-app")
        }
    }

    @Test("만료된 라이선스 파일 거부")
    func testExpiredLicense() throws {
        let (privateKey, publicKey) = OfflineLicenseValidator.generateKeyPair()
        let fixedNow = Date(timeIntervalSince1970: 1750000000)
        let validator = OfflineLicenseValidator(publicKey: publicKey, now: { fixedNow })

        let issued = try OfflineLicenseValidator.sign(
            bundleId: "kr.gujo.test-app",
            issuedAt: Date(timeIntervalSince1970: 1700000000),
            expiresAt: Date(timeIntervalSince1970: 1740000000), // 과거 만료
            privateKey: privateKey
        )

        #expect(throws: OfflineLicenseError.expired) {
            try validator.validate(jsonString: issued.json)
        }
    }

    @Test("위조되거나 변조된 서명 거부")
    func testTamperedSignature() throws {
        let (privateKey, publicKey) = OfflineLicenseValidator.generateKeyPair()
        let validator = OfflineLicenseValidator(publicKey: publicKey)

        let issued = try OfflineLicenseValidator.sign(
            bundleId: "kr.gujo.test-app",
            privateKey: privateKey
        )

        // 서명 일부 변조
        var tampered = issued.file
        tampered.signature = "invalidSignatureValueBase64url=="

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(tampered)

        #expect(throws: OfflineLicenseError.self) {
            try validator.validate(data: data)
        }
    }

    @Test("다른 공개키로 검증 시 거부")
    func testWrongPublicKey() throws {
        let (privateKey1, _) = OfflineLicenseValidator.generateKeyPair()
        let (_, publicKey2) = OfflineLicenseValidator.generateKeyPair()
        let validator = OfflineLicenseValidator(publicKey: publicKey2)

        let issued = try OfflineLicenseValidator.sign(
            bundleId: "kr.gujo.test-app",
            privateKey: privateKey1
        )

        #expect(throws: OfflineLicenseError.invalidSignature) {
            try validator.validate(jsonString: issued.json)
        }
    }

    @Test("번들 내장 공개키 유효성 확인")
    func testBundledPublicKeyIsValid() throws {
        let defaultValidator = OfflineLicenseValidator()
        guard let pubData = Data(base64URLOrStandard: defaultValidator.publicKey) else {
            Issue.record("공개키 base64 디코딩 실패")
            return
        }
        #expect(pubData.count == 32)
        #expect(throws: Never.self) {
            _ = try Curve25519.Signing.PublicKey(rawRepresentation: pubData)
        }
    }
}
