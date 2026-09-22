import Foundation
import CryptoKit
import Testing
@testable import LicenseCacheKit

@Suite("OfflineLicenseStore Tests")
struct OfflineLicenseStoreTests {

    @Test("라이선스 파일 활성화 및 조회 성공")
    func testActivateAndLoadLicense() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let (privateKey, publicKey) = OfflineLicenseValidator.generateKeyPair()
        let validator = OfflineLicenseValidator(publicKey: publicKey)
        let store = OfflineLicenseStore(directory: tempDir, validator: validator)

        let issued = try OfflineLicenseValidator.sign(
            bundleId: "kr.gujo.editor",
            plan: "team",
            customer: "alice",
            privateKey: privateKey
        )

        // 활성화
        let activated = try store.activate(jsonString: issued.json)
        #expect(activated.bundleId == "kr.gujo.editor")
        #expect(activated.plan == "team")

        // 조회
        let loaded = store.load(for: "kr.gujo.editor")
        #expect(loaded != nil)
        #expect(loaded?.bundleId == "kr.gujo.editor")
        #expect(loaded?.customer == "alice")
        #expect(store.hasValidLicense(for: "kr.gujo.editor"))
        #expect(!store.hasValidLicense(for: "kr.gujo.other"))

        // 목록
        let list = store.list()
        #expect(list.count == 1)
        #expect(list.first?.bundleId == "kr.gujo.editor")

        // 삭제
        try store.remove(for: "kr.gujo.editor")
        #expect(!store.hasValidLicense(for: "kr.gujo.editor"))
    }

    @Test("잘못된 서명의 라이선스는 활성화 거부")
    func testInvalidSignatureRejected() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let (_, publicKey) = OfflineLicenseValidator.generateKeyPair()
        let validator = OfflineLicenseValidator(publicKey: publicKey)
        let store = OfflineLicenseStore(directory: tempDir, validator: validator)

        let invalidJson = """
        {
            "bundleId": "kr.gujo.editor",
            "plan": "team",
            "issuedAt": "2026-01-01T00:00:00Z",
            "signature": "invalidSig"
        }
        """

        #expect(throws: OfflineLicenseError.self) {
            try store.activate(jsonString: invalidJson)
        }
        #expect(!store.hasValidLicense(for: "kr.gujo.editor"))
    }

    @Test("만료된 라이선스는 활성화 거부")
    func testExpiredLicenseRejected() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let (privateKey, publicKey) = OfflineLicenseValidator.generateKeyPair()
        let fixedNow = Date(timeIntervalSince1970: 1750000000)
        let validator = OfflineLicenseValidator(publicKey: publicKey, now: { fixedNow })
        let store = OfflineLicenseStore(directory: tempDir, validator: validator)

        let issued = try OfflineLicenseValidator.sign(
            bundleId: "kr.gujo.editor",
            issuedAt: Date(timeIntervalSince1970: 1700000000),
            expiresAt: Date(timeIntervalSince1970: 1740000000),
            privateKey: privateKey
        )

        #expect(throws: OfflineLicenseError.expired) {
            try store.activate(jsonString: issued.json)
        }
        #expect(!store.hasValidLicense(for: "kr.gujo.editor"))
    }

    @Test("bundleId 불일치 시 활성화 거부")
    func testBundleIdMismatchRejected() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let (privateKey, publicKey) = OfflineLicenseValidator.generateKeyPair()
        let validator = OfflineLicenseValidator(publicKey: publicKey)
        let store = OfflineLicenseStore(directory: tempDir, validator: validator)

        let issued = try OfflineLicenseValidator.sign(
            bundleId: "kr.gujo.wrong-app",
            privateKey: privateKey
        )

        #expect(throws: OfflineLicenseError.self) {
            try store.activate(jsonString: issued.json, expectedBundleId: "kr.gujo.expected-app")
        }
    }
}
