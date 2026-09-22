import Foundation

public protocol ClipboardSyncStore: Sendable {
    func dirty(limit: Int) async -> [StoredClipboardClip]
    func find(id: String) async -> StoredClipboardClip?
    func upsert(_ value: StoredClipboardClip) async
    func markSyncedIfUnchanged(_ value: StoredClipboardClip) async
}

public protocol SyncCredentialsStore: Sendable {
    func load() async -> SyncCredentials?
    func save(_ credentials: SyncCredentials) async throws
    func clear() async
}

public enum SyncResult: Equatable, Sendable {
    case success(uploaded: Int, downloaded: Int, corruptEnvelopes: Int, route: SyncTransportRoute)
    case notConfigured
    case retryable
    case rePairRequired
}

public enum SyncTransportRoute: Equatable, Sendable { case lan, relay }

public actor SyncCoordinator {
    private let store: any ClipboardSyncStore
    private let relay: any RelayTransport
    private let credentials: any SyncCredentialsStore
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let nonceSource: @Sendable () -> Data
    private let pageSize = 200

    public init(
        store: any ClipboardSyncStore,
        relay: any RelayTransport,
        credentials: any SyncCredentialsStore,
        nonceSource: @escaping @Sendable () -> Data = { Data((0..<12).map { _ in UInt8.random(in: .min ... .max) }) }
    ) {
        self.store = store
        self.relay = relay
        self.credentials = credentials
        self.nonceSource = nonceSource
    }

    public func sync() async -> SyncResult {
        guard var credential = await credentials.load() else { return .notConfigured }
        do {
            let dirty = await store.dirty(limit: pageSize)
            if !dirty.isEmpty {
                let envelopes = try dirty.map { try encrypt($0.clip, credential: credential) }
                _ = try await relay.upload(token: credential.token, envelopes: envelopes)
                for value in dirty { await store.markSyncedIfUnchanged(value) }
            }

            var downloaded = 0
            var corrupt = 0
            var resetCursor = false
            while true {
                let page: ChangePage
                do {
                    page = try await relay.changes(token: credential.token, cursor: credential.cursor, limit: pageSize)
                } catch RelayError.cursorExpired where !resetCursor {
                    resetCursor = true
                    credential.cursor = nil
                    try await credentials.save(credential)
                    continue
                }
                for envelope in page.envelopes {
                    do {
                        let plaintext = try ClipboardCryptoBox.open(envelope: envelope, key: credential.groupKey)
                        let clip = try decoder.decode(ClipboardClip.self, from: Data(plaintext.utf8))
                        guard clip.id == envelope.clipId, clip.updatedAt == envelope.updatedAt else {
                            throw ClipboardCryptoError.invalidCiphertext
                        }
                        try await merge(clip)
                        downloaded += 1
                    } catch { corrupt += 1 }
                }
                let previous = credential.cursor
                credential.cursor = page.nextCursor ?? previous
                try await credentials.save(credential)
                if page.envelopes.count < pageSize || page.nextCursor == nil || page.nextCursor == previous { break }
            }
            return .success(
                uploaded: dirty.count, downloaded: downloaded,
                corruptEnvelopes: corrupt, route: .relay)
        } catch RelayError.unauthorized {
            return .rePairRequired
        } catch RelayError.retryable {
            return .retryable
        } catch {
            return .retryable
        }
    }

    private func encrypt(_ clip: ClipboardClip, credential: SyncCredentials) throws -> EncryptedEnvelope {
        let text = String(decoding: try encoder.encode(clip), as: UTF8.self)
        return try ClipboardCryptoBox.seal(
            plaintext: text,
            key: credential.groupKey,
            metadata: EnvelopeMetadata(
                vaultId: credential.vaultId,
                clipId: clip.id,
                updatedAt: clip.updatedAt,
                operation: clip.deletedAt == nil ? .upsert : .delete),
            nonce: nonceSource())
    }

    private func merge(_ remote: ClipboardClip) async throws {
        guard let local = await store.find(id: remote.id) else {
            await store.upsert(StoredClipboardClip(clip: remote, syncState: .synced))
            return
        }
        let resolved = ClipboardConflictResolver.resolve(local: local.clip, remote: remote)
        if resolved != local.clip {
            await store.upsert(StoredClipboardClip(clip: resolved, syncState: .synced))
        }
    }
}
