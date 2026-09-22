import ClipboardSyncKit
import Foundation
import Testing

@Suite("Swift pairing")
struct PairingTests {
    @Test func androidCompatiblePairingQRRoundTripsAndDetectsKeySubstitution() throws {
        let key = Data(repeating: 9, count: 32)
        let payload = try PairingQRCodec.prepare(
            PairingQRPayload(
                relayUrl: "https://relay.test", vaultId: "vault", inviteId: "invite",
                expiresAt: 99, issuerDeviceId: "android", groupKey: key.base64EncodedString()),
            groupKey: key)
        let encoded = try PairingQRCodec.encode(payload)

        #expect(try PairingQRCodec.verify(PairingQRCodec.decode(encoded)))
        #expect(throws: InvalidPairingQRError.self) {
            var changed = payload
            changed.groupKey = Data(repeating: 8, count: 32).base64EncodedString()
            _ = try PairingQRCodec.verify(changed)
        }
    }
}
