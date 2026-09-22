import Foundation

public actor SwiftLanClipboardCoordinator {
    private let store: any ClipboardSyncStore
    private let credentials: any SyncCredentialsStore
    private let deviceId: String
    private let discovery: SwiftLanDiscovery
    private let client = SwiftLanSyncClient()
    private var server: SwiftLanServer?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var servePager = SwiftDirtyBatchPager()

    public init(store: any ClipboardSyncStore, credentials: any SyncCredentialsStore, deviceId: String) {
        self.store = store
        self.credentials = credentials
        self.deviceId = deviceId
        discovery = SwiftLanDiscovery(deviceId: deviceId)
    }

    public func start() async throws {
        guard server == nil else { return }
        let value = SwiftLanServer(
            deviceId: deviceId,
            groupKeyProvider: { [credentials] in await credentials.load()?.groupKey },
            exchange: { [weak self] incoming in await self?.serve(incoming) ?? [] })
        _ = try await value.start(advertise: true)
        server = value
        discovery.start()
    }

    public func stop() { server?.stop(); server = nil; discovery.stop() }

    public func sync() async throws -> SyncResult {
        guard let credential = await credentials.load() else { return .notConfigured }
        let peers = discovery.peers
        guard !peers.isEmpty else { throw SwiftLanError.unavailable }
        let dirty = await store.dirty(limit: 200)
        let outgoing = try dirty.map { try encrypt($0.clip, credential: credential) }
        let client = self.client
        let requesterDeviceId = deviceId
        let groupKey = credential.groupKey
        let incoming: [EncryptedEnvelope] = try await firstSuccessfulLanPeer(peers) { peer in
            try await client.exchange(
                    peer: peer,
                    requesterDeviceId: requesterDeviceId,
                    groupKey: groupKey,
                    envelopes: outgoing,
                    timeout: .seconds(2))
        }
        for value in dirty { await store.markSyncedIfUnchanged(value) }
        let merged = await merge(incoming, key: credential.groupKey)
        return .success(
            uploaded: dirty.count, downloaded: merged.downloaded,
            corruptEnvelopes: merged.corrupt, route: .lan)
    }

    private func serve(_ incoming: [EncryptedEnvelope]) async -> [EncryptedEnvelope] {
        guard let credential = await credentials.load() else { return [] }
        _ = await merge(incoming, key: credential.groupKey)
        let candidates = await store.dirty(limit: servePager.requestLimit(pageSize: 200))
        return servePager.next(candidates: candidates, pageSize: 200)
            .compactMap { try? encrypt($0.clip, credential: credential) }
    }

    private func merge(_ envelopes: [EncryptedEnvelope], key: Data) async -> (downloaded: Int, corrupt: Int) {
        var downloaded = 0
        var corrupt = 0
        for envelope in envelopes {
            do {
                let text = try ClipboardCryptoBox.open(envelope: envelope, key: key)
                let remote = try decoder.decode(ClipboardClip.self, from: Data(text.utf8))
                guard remote.id == envelope.clipId, remote.updatedAt == envelope.updatedAt else {
                    throw SwiftLanError.invalidResponse
                }
                if let local = await store.find(id: remote.id) {
                    let resolved = ClipboardConflictResolver.resolve(local: local.clip, remote: remote)
                    if resolved != local.clip {
                        await store.upsert(StoredClipboardClip(clip: resolved, syncState: .synced))
                    }
                } else {
                    await store.upsert(StoredClipboardClip(clip: remote, syncState: .synced))
                }
                downloaded += 1
            } catch { corrupt += 1 }
        }
        return (downloaded, corrupt)
    }

    private func encrypt(_ clip: ClipboardClip, credential: SyncCredentials) throws -> EncryptedEnvelope {
        try ClipboardCryptoBox.seal(
            plaintext: String(decoding: try encoder.encode(clip), as: UTF8.self),
            key: credential.groupKey,
            metadata: EnvelopeMetadata(
                vaultId: credential.vaultId, clipId: clip.id, updatedAt: clip.updatedAt,
                operation: clip.deletedAt == nil ? .upsert : .delete),
            nonce: Data((0..<12).map { _ in UInt8.random(in: .min ... .max) }))
    }
}

func firstSuccessfulLanPeer<T: Sendable>(
    _ peers: [SwiftLanPeer],
    attempt: @Sendable (SwiftLanPeer) async throws -> T
) async throws -> T {
    var lastError: Error = SwiftLanError.unavailable
    for peer in peers {
        do { return try await attempt(peer) }
        catch { lastError = error }
    }
    throw lastError
}

struct SwiftDirtyBatchPager {
    private var offset = 0

    mutating func requestLimit(pageSize: Int) -> Int { offset + pageSize }

    mutating func next<T>(candidates: [T], pageSize: Int) -> [T] {
        if candidates.count <= offset { offset = 0 }
        let page = Array(candidates.dropFirst(offset).prefix(pageSize))
        offset = page.count < pageSize ? 0 : offset + page.count
        return page
    }
}

public actor SwiftHybridSyncCoordinator {
    private let lan: SwiftLanClipboardCoordinator
    private let relay: SyncCoordinator
    public init(lan: SwiftLanClipboardCoordinator, relay: SyncCoordinator) {
        self.lan = lan; self.relay = relay
    }
    public func startLAN() async { try? await lan.start() }
    public func sync() async -> SyncResult {
        do { return try await lan.sync() }
        catch { return await relay.sync() }
    }
}
