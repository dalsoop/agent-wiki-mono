#if canImport(CryptoKit)
import CryptoKit
import Foundation

public struct PairingQRPayload: Codable, Equatable, Sendable {
    public var protocolVersion: Int
    public var relayUrl: String
    public var vaultId: String
    public var inviteId: String
    public var expiresAt: Int64
    public var issuerDeviceId: String
    public var groupKey: String
    public var keyFingerprint: String

    public init(
        protocolVersion: Int = 1,
        relayUrl: String,
        vaultId: String,
        inviteId: String,
        expiresAt: Int64,
        issuerDeviceId: String,
        groupKey: String,
        keyFingerprint: String = ""
    ) {
        self.protocolVersion = protocolVersion
        self.relayUrl = relayUrl
        self.vaultId = vaultId
        self.inviteId = inviteId
        self.expiresAt = expiresAt
        self.issuerDeviceId = issuerDeviceId
        self.groupKey = groupKey
        self.keyFingerprint = keyFingerprint
    }

    public func replacing(vaultId: String) -> Self {
        var copy = self; copy.vaultId = vaultId; return copy
    }
}

public struct InvalidPairingQRError: Error, Equatable, Sendable { public init() {} }

public enum PairingQRCodec {
    private static let prefix = "clipboard-sync://pair?data="

    public static func prepare(_ payload: PairingQRPayload, groupKey: Data) throws -> PairingQRPayload {
        guard groupKey.count == 32 else { throw InvalidPairingQRError() }
        var value = payload
        value.keyFingerprint = Data(SHA256.hash(data: groupKey)).base64EncodedString()
        return value
    }

    public static func verify(_ payload: PairingQRPayload) throws -> Bool {
        guard payload.protocolVersion == 1,
              let key = Data(base64Encoded: payload.groupKey), key.count == 32
        else { throw InvalidPairingQRError() }
        let expected = Data(SHA256.hash(data: key)).base64EncodedString()
        guard let actualData = Data(base64Encoded: payload.keyFingerprint),
              let expectedData = Data(base64Encoded: expected),
              actualData == expectedData
        else { throw InvalidPairingQRError() }
        return true
    }

    public static func encode(_ payload: PairingQRPayload) throws -> String {
        let data = try JSONEncoder().encode(payload)
        return prefix + data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    public static func decode(_ value: String) throws -> PairingQRPayload {
        guard value.hasPrefix(prefix) else { throw InvalidPairingQRError() }
        var encoded = String(value.dropFirst(prefix.count)).replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
        guard let data = Data(base64Encoded: encoded),
              let payload = try? JSONDecoder().decode(PairingQRPayload.self, from: data)
        else { throw InvalidPairingQRError() }
        return payload
    }
}
#endif
