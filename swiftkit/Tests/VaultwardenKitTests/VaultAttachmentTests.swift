import XCTest
@testable import VaultwardenKit

final class VaultAttachmentCryptoTests: XCTestCase {
    private func makeKey() -> BitwardenCrypto.SymmetricKeySet {
        VaultAttachmentCrypto.makeAttachmentKey()
    }

    func testRoundTripPreservesBytes() throws {
        let key = makeKey()
        let original = Data("사업자등록증 PDF 내용 \u{1F4C4}".utf8) + Data((0..<5000).map { UInt8($0 % 251) })
        let sealed = try VaultAttachmentCrypto.encrypt(original, key: key)
        // 헤더(type 1 + iv 16 + mac 32) 뒤에 암호문이 온다 — 공식 클라이언트와 같은 레이아웃.
        XCTAssertEqual(sealed.first, 2)
        XCTAssertGreaterThan(sealed.count, original.count)
        let opened = try VaultAttachmentCrypto.decrypt(sealed, key: key)
        XCTAssertEqual(opened, original)
    }

    func testEmptyFileRoundTrip() throws {
        let key = makeKey()
        let sealed = try VaultAttachmentCrypto.encrypt(Data(), key: key)
        XCTAssertEqual(try VaultAttachmentCrypto.decrypt(sealed, key: key), Data())
    }

    func testWrongKeyFails() throws {
        let sealed = try VaultAttachmentCrypto.encrypt(Data("secret".utf8), key: makeKey())
        XCTAssertThrowsError(try VaultAttachmentCrypto.decrypt(sealed, key: makeKey()))
    }

    func testTamperedCiphertextFailsMAC() throws {
        let key = makeKey()
        var sealed = try VaultAttachmentCrypto.encrypt(Data("중요 서류".utf8), key: key)
        sealed[sealed.count - 1] ^= 0xFF
        XCTAssertThrowsError(try VaultAttachmentCrypto.decrypt(sealed, key: key))
    }

    func testRejectsShortOrUnsupportedBuffers() {
        let key = makeKey()
        XCTAssertThrowsError(try VaultAttachmentCrypto.decrypt(Data(), key: key))
        XCTAssertThrowsError(try VaultAttachmentCrypto.decrypt(Data([2, 0, 0]), key: key))
        // type 1(AES-CBC no MAC)은 첨부에서 쓰지 않는다.
        var unsupported = Data([1])
        unsupported.append(Data(repeating: 0, count: 64))
        XCTAssertThrowsError(try VaultAttachmentCrypto.decrypt(unsupported, key: key))
    }

    func testAttachmentKeyIs64BytesAndRandom() {
        let first = VaultAttachmentCrypto.makeAttachmentKey()
        let second = VaultAttachmentCrypto.makeAttachmentKey()
        XCTAssertEqual(first.raw.count, 64)
        XCTAssertEqual(first.enc.count, 32)
        XCTAssertEqual(first.mac.count, 32)
        XCTAssertNotEqual(first.raw, second.raw)
    }

    /// 첨부 키는 항목 키로 감싸 서버에 올린다 — 그 왕복이 깨지면 다운로드가 불가능해진다.
    func testAttachmentKeyWrapUnwrap() throws {
        let itemKey = VaultAttachmentCrypto.makeAttachmentKey()
        let attachmentKey = VaultAttachmentCrypto.makeAttachmentKey()
        let wrapped = try BitwardenCrypto.encrypt(attachmentKey.raw, key: itemKey).serialized
        let raw = try BitwardenCrypto.decrypt(BitwardenCrypto.EncString(parse: wrapped), key: itemKey)
        XCTAssertEqual(BitwardenCrypto.SymmetricKeySet(raw: raw)?.raw, attachmentKey.raw)
    }

    func testHumanSize() {
        XCTAssertEqual(VaultAttachmentCrypto.humanSize(512), "512 B")
        XCTAssertEqual(VaultAttachmentCrypto.humanSize(2048), "2.0 KB")
        XCTAssertEqual(VaultAttachmentCrypto.humanSize(5 * 1024 * 1024), "5.0 MB")
    }
}
