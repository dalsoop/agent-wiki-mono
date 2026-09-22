#if canImport(CryptoKit)
import CryptoKit
import Foundation

public enum ClipboardCryptoError: Error, Equatable {
    case invalidKey
    case invalidNonce
    case invalidCiphertext
    case unsupportedVersion
}

public enum ClipboardCryptoBox {
    public static func seal(
        plaintext: String,
        key: Data,
        metadata: EnvelopeMetadata,
        nonce: Data
    ) throws -> EncryptedEnvelope {
        guard key.count == 32 else { throw ClipboardCryptoError.invalidKey }
        guard nonce.count == 12 else { throw ClipboardCryptoError.invalidNonce }
        let sealed = try AES.GCM.seal(
            Data(plaintext.utf8),
            using: SymmetricKey(data: key),
            nonce: try AES.GCM.Nonce(data: nonce),
            authenticating: metadata.authenticatedData)
        return EncryptedEnvelope(
            vaultId: metadata.vaultId,
            clipId: metadata.clipId,
            updatedAt: metadata.updatedAt,
            operation: metadata.operation,
            nonce: nonce.base64EncodedString(),
            ciphertext: (sealed.ciphertext + sealed.tag).base64EncodedString())
    }

    public static func open(envelope: EncryptedEnvelope, key: Data) throws -> String {
        guard envelope.version == 1 else { throw ClipboardCryptoError.unsupportedVersion }
        guard key.count == 32 else { throw ClipboardCryptoError.invalidKey }
        guard let nonceData = Data(base64Encoded: envelope.nonce), nonceData.count == 12 else {
            throw ClipboardCryptoError.invalidNonce
        }
        guard let combined = Data(base64Encoded: envelope.ciphertext), combined.count >= 16 else {
            throw ClipboardCryptoError.invalidCiphertext
        }
        let split = combined.count - 16
        let box = try AES.GCM.SealedBox(
            nonce: AES.GCM.Nonce(data: nonceData),
            ciphertext: combined.prefix(split),
            tag: combined.suffix(16))
        let plaintext = try AES.GCM.open(
            box, using: SymmetricKey(data: key), authenticating: envelope.metadata.authenticatedData)
        guard let value = String(data: plaintext, encoding: .utf8) else {
            throw ClipboardCryptoError.invalidCiphertext
        }
        return value
    }
}
#endif
