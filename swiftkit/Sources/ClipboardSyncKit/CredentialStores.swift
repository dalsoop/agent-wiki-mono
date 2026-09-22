import Foundation
import Security

public actor KeychainSyncCredentialsStore: SyncCredentialsStore {
    private let service: String
    private let account: String

    public init(service: String, account: String = "sync-credentials") {
        self.service = service
        self.account = account
    }

    public func load() -> SyncCredentials? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return try? JSONDecoder().decode(SyncCredentials.self, from: data)
    }

    public func save(_ credentials: SyncCredentials) throws {
        let data = try JSONEncoder().encode(credentials)
        SecItemDelete(baseQuery as CFDictionary)
        var query = baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else {
            throw KeychainCredentialError.writeFailed
        }
    }

    public func clear() { SecItemDelete(baseQuery as CFDictionary) }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

public enum KeychainCredentialError: Error { case writeFailed }

public actor PairingCoordinator {
    private let relayURL: URL
    private let relay: any RelayTransport
    private let credentials: any SyncCredentialsStore
    private let deviceId: String
    private let deviceName: String

    public init(
        relayURL: URL,
        relay: any RelayTransport,
        credentials: any SyncCredentialsStore,
        deviceId: String,
        deviceName: String
    ) {
        self.relayURL = relayURL
        self.relay = relay
        self.credentials = credentials
        self.deviceId = deviceId
        self.deviceName = deviceName
    }

    public func createInvitation() async throws -> PairingQRPayload {
        let value: SyncCredentials
        if let stored = await credentials.load() {
            value = stored
        } else {
            let issued = try await relay.createVault(deviceId: deviceId, deviceName: deviceName)
            var key = Data(count: 32)
            let status = key.withUnsafeMutableBytes {
                SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!)
            }
            guard status == errSecSuccess else { throw InvalidPairingQRError() }
            value = SyncCredentials(
                vaultId: issued.vaultId, deviceId: issued.deviceId, token: issued.token, groupKey: key)
            try await credentials.save(value)
        }
        let prepared = try PairingQRCodec.prepare(
            PairingQRPayload(
                relayUrl: relayURL.absoluteString,
                vaultId: value.vaultId,
                inviteId: "",
                expiresAt: 0,
                issuerDeviceId: value.deviceId,
                groupKey: value.groupKey.base64EncodedString()),
            groupKey: value.groupKey)
        let invite = try await relay.createInvite(
            token: value.token, keyFingerprint: prepared.keyFingerprint)
        var payload = prepared
        payload.inviteId = invite.inviteId
        payload.expiresAt = invite.expiresAt
        return payload
    }

    public func acceptInvitation(_ text: String) async throws {
        let payload = try PairingQRCodec.decode(text)
        _ = try PairingQRCodec.verify(payload)
        guard let groupKey = Data(base64Encoded: payload.groupKey) else { throw InvalidPairingQRError() }
        let issued = try await relay.exchangeInvite(
            inviteId: payload.inviteId, deviceId: deviceId, deviceName: deviceName,
            keyFingerprint: payload.keyFingerprint)
        guard issued.vaultId == payload.vaultId else { throw InvalidPairingQRError() }
        try await credentials.save(SyncCredentials(
            vaultId: issued.vaultId, deviceId: issued.deviceId, token: issued.token, groupKey: groupKey))
    }

    public func disconnect() async { await credentials.clear() }
}
