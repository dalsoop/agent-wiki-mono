import ClipboardSyncKit
import Foundation
import Testing

@Suite("Swift sync coordinator")
struct SyncCoordinatorTests {
    @Test func uploadHappensBeforeDownloadAndCursorAdvances() async throws {
        let store = MemoryClipStore(items: [sampleClip(id: "local", updatedAt: 10)])
        let credentials = MemoryCredentialsStore(value: SyncCredentials(
            vaultId: "vault", deviceId: "mac", token: "token", groupKey: Data(repeating: 7, count: 32)))
        let relay = RecordingRelay()
        let coordinator = SyncCoordinator(store: store, relay: relay, credentials: credentials)

        let result = await coordinator.sync()

        #expect(result == .success(uploaded: 1, downloaded: 0, corruptEnvelopes: 0, route: .relay))
        #expect(await relay.calls == ["upload", "changes:nil"])
        #expect(await credentials.load()?.cursor == "1")
    }

    @Test func unauthorizedRequiresPairingWithoutRetry() async {
        let store = MemoryClipStore(items: [sampleClip(id: "local", updatedAt: 10)])
        let credentials = MemoryCredentialsStore(value: SyncCredentials(
            vaultId: "vault", deviceId: "mac", token: "revoked", groupKey: Data(repeating: 7, count: 32)))
        let relay = RecordingRelay(failure: .unauthorized)

        let result = await SyncCoordinator(store: store, relay: relay, credentials: credentials).sync()

        #expect(result == .rePairRequired)
        #expect(await relay.calls == ["upload"])
    }
}

private func sampleClip(id: String, updatedAt: Int64) -> ClipboardClip {
    ClipboardClip(id: id, createdAt: 1, updatedAt: updatedAt, sourceDeviceId: "mac", text: id, isFavorite: false)
}

private actor MemoryClipStore: ClipboardSyncStore {
    var rows: [String: StoredClipboardClip]
    init(items: [ClipboardClip]) { rows = Dictionary(uniqueKeysWithValues: items.map { ($0.id, StoredClipboardClip(clip: $0, syncState: .dirtyUpsert)) }) }
    func dirty(limit: Int) -> [StoredClipboardClip] { Array(rows.values.prefix(limit)) }
    func find(id: String) -> StoredClipboardClip? { rows[id] }
    func upsert(_ value: StoredClipboardClip) { rows[value.clip.id] = value }
    func markSyncedIfUnchanged(_ value: StoredClipboardClip) {
        guard rows[value.clip.id] == value else { return }
        rows[value.clip.id]?.syncState = .synced
    }
}

private actor MemoryCredentialsStore: SyncCredentialsStore {
    var value: SyncCredentials?
    init(value: SyncCredentials?) { self.value = value }
    func load() -> SyncCredentials? { value }
    func save(_ credentials: SyncCredentials) { value = credentials }
    func clear() { value = nil }
}

private actor RecordingRelay: RelayTransport {
    var calls: [String] = []
    let failure: RelayError?
    init(failure: RelayError? = nil) { self.failure = failure }
    func createVault(deviceId: String, deviceName: String) async throws -> VaultCredentials { fatalError() }
    func createInvite(token: String, keyFingerprint: String) async throws -> RelayInvite { fatalError() }
    func exchangeInvite(
        inviteId: String, deviceId: String, deviceName: String, keyFingerprint: String
    ) async throws -> VaultCredentials { fatalError() }
    func upload(token: String, envelopes: [EncryptedEnvelope]) async throws -> [String] {
        calls.append("upload")
        if let failure { throw failure }
        return ["1"]
    }
    func changes(token: String, cursor: String?, limit: Int) async throws -> ChangePage {
        calls.append("changes:\(cursor ?? "nil")")
        return ChangePage(envelopes: [], nextCursor: "1")
    }
}
