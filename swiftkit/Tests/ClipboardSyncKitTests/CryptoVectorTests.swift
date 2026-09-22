import ClipboardSyncKit
import Foundation
import Testing

@Suite("clipboard-sync-v1 crypto")
struct CryptoVectorTests {
    @Test func kotlinAESGCMVectorMatchesExactly() throws {
        let key = Data(base64Encoded: "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=")!
        let nonce = Data(base64Encoded: "EBESExQVFhcYGRob")!
        let metadata = EnvelopeMetadata(
            vaultId: "vault-korean",
            clipId: "018f0000-0000-7000-8000-000000000001",
            updatedAt: 1_784_246_400_000,
            operation: .upsert)

        let envelope = try ClipboardCryptoBox.seal(
            plaintext: "안녕하세요 clipboard", key: key, metadata: metadata, nonce: nonce)

        #expect(envelope.ciphertext == "kWsQ/cxc1yZSmYyl4+P9c7Q8J355rTbDg+w59EPOxcB7U6ncsqjF3x0=")
        #expect(try ClipboardCryptoBox.open(envelope: envelope, key: key) == "안녕하세요 clipboard")
    }

    @Test func modifiedAADIsRejected() throws {
        let key = Data(repeating: 1, count: 32)
        let envelope = try ClipboardCryptoBox.seal(
            plaintext: "secret",
            key: key,
            metadata: EnvelopeMetadata(vaultId: "v", clipId: "c", updatedAt: 1, operation: .upsert),
            nonce: Data(repeating: 2, count: 12))

        #expect(throws: (any Error).self) {
            _ = try ClipboardCryptoBox.open(envelope: envelope.replacing(updatedAt: 2), key: key)
        }
    }

    @Test func kotlinEnvelopeFixtureDecodes() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appending(path: "protocols/clipboard-sync-v1/envelopes.json"))
        let values = try JSONDecoder().decode([EncryptedEnvelope].self, from: data)
        #expect(values.count == 2)
        #expect(values[0].operation == .upsert)
        #expect(values[1].operation == .delete)
    }
}
