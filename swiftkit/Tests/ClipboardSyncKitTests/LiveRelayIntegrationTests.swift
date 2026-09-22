import ClipboardSyncKit
import Foundation
import Testing

@Suite("Live relay with production Swift client", .serialized)
struct LiveRelayIntegrationTests {
    @Test func pairRevokeRepairAndEncryptedSync() async throws {
        guard let rawURL = ProcessInfo.processInfo.environment["CLIPBOARD_SYNC_LIVE_URL"],
              let url = URL(string: rawURL) else { return }
        let suffix = UUID().uuidString.lowercased()
        let relay = RelayClient(baseURL: url)
        let ownerCredentials = LiveCredentialsStore()
        let peerCredentials = LiveCredentialsStore()
        let ownerPairing = PairingCoordinator(
            relayURL: url, relay: relay, credentials: ownerCredentials,
            deviceId: "swift-owner-\(suffix)", deviceName: "Swift live owner")
        let peerPairing = PairingCoordinator(
            relayURL: url, relay: relay, credentials: peerCredentials,
            deviceId: "swift-peer-\(suffix)", deviceName: "Swift live peer")

        let firstQR = try PairingQRCodec.encode(try await ownerPairing.createInvitation())
        try await peerPairing.acceptInvitation(firstQR)
        let owner = try #require(await ownerCredentials.load())
        let oldPeer = try #require(await peerCredentials.load())
        try await relay.revokeDevice(token: owner.token, deviceId: oldPeer.deviceId)
        await #expect(throws: RelayError.unauthorized) {
            _ = try await relay.changes(token: oldPeer.token, cursor: nil, limit: 1)
        }

        let secondQR = try PairingQRCodec.encode(try await ownerPairing.createInvitation())
        try await peerPairing.acceptInvitation(secondQR)
        let repairedPeer = try #require(await peerCredentials.load())
        #expect(repairedPeer.deviceId == oldPeer.deviceId)
        #expect(repairedPeer.token != oldPeer.token)

        let clip = ClipboardClip(
            id: UUID().uuidString.lowercased(), createdAt: 1, updatedAt: 2,
            sourceDeviceId: owner.deviceId, text: "swift-production-live", isFavorite: true)
        let ownerStore = LiveClipStore(initial: clip)
        let peerStore = LiveClipStore()
        #expect(await SyncCoordinator(store: ownerStore, relay: relay, credentials: ownerCredentials).sync()
            == .success(uploaded: 1, downloaded: 1, corruptEnvelopes: 0, route: .relay))
        let peerResult = await SyncCoordinator(store: peerStore, relay: relay, credentials: peerCredentials).sync()
        guard case .success(_, let downloaded, let corrupt, .relay) = peerResult else {
            Issue.record("peer sync failed: \(peerResult)")
            return
        }
        #expect(downloaded >= 1)
        #expect(corrupt == 0)
        #expect(await peerStore.find(id: clip.id)?.clip == clip)
    }
}

private actor LiveCredentialsStore: SyncCredentialsStore {
    private var value: SyncCredentials?
    func load() -> SyncCredentials? { value }
    func save(_ credentials: SyncCredentials) { value = credentials }
    func clear() { value = nil }
}

private actor LiveClipStore: ClipboardSyncStore {
    private var rows: [String: StoredClipboardClip] = [:]
    init(initial: ClipboardClip? = nil) {
        if let initial { rows[initial.id] = StoredClipboardClip(clip: initial, syncState: .dirtyUpsert) }
    }
    func dirty(limit: Int) -> [StoredClipboardClip] {
        Array(rows.values.filter { $0.syncState != .synced }.prefix(limit))
    }
    func find(id: String) -> StoredClipboardClip? { rows[id] }
    func upsert(_ value: StoredClipboardClip) { rows[value.clip.id] = value }
    func markSyncedIfUnchanged(_ value: StoredClipboardClip) {
        guard rows[value.clip.id] == value else { return }
        rows[value.clip.id]?.syncState = .synced
    }
}
