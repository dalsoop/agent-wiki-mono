import Foundation

public enum EnvelopeOperation: String, Codable, Sendable {
    case upsert
    case delete
}

public struct ClipboardClip: Codable, Equatable, Sendable {
    public var id: String
    public var createdAt: Int64
    public var updatedAt: Int64
    public var sourceDeviceId: String
    public var text: String
    public var isFavorite: Bool
    public var deletedAt: Int64?

    public init(
        id: String,
        createdAt: Int64,
        updatedAt: Int64,
        sourceDeviceId: String,
        text: String,
        isFavorite: Bool,
        deletedAt: Int64? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sourceDeviceId = sourceDeviceId
        self.text = text
        self.isFavorite = isFavorite
        self.deletedAt = deletedAt
    }
}

public enum ClipSyncState: String, Codable, Sendable {
    case dirtyUpsert = "dirty-upsert"
    case dirtyDelete = "dirty-delete"
    case synced
}

public struct StoredClipboardClip: Codable, Equatable, Sendable {
    public var clip: ClipboardClip
    public var syncState: ClipSyncState
    public init(clip: ClipboardClip, syncState: ClipSyncState) {
        self.clip = clip
        self.syncState = syncState
    }
}

public struct EnvelopeMetadata: Equatable, Sendable {
    public var vaultId: String
    public var clipId: String
    public var updatedAt: Int64
    public var operation: EnvelopeOperation

    public init(vaultId: String, clipId: String, updatedAt: Int64, operation: EnvelopeOperation) {
        self.vaultId = vaultId
        self.clipId = clipId
        self.updatedAt = updatedAt
        self.operation = operation
    }

    public var authenticatedData: Data {
        Data("v1|\(vaultId)|\(clipId)|\(updatedAt)|\(operation.rawValue)".utf8)
    }
}

public struct EncryptedEnvelope: Codable, Equatable, Sendable {
    public var version: Int
    public var vaultId: String
    public var clipId: String
    public var updatedAt: Int64
    public var operation: EnvelopeOperation
    public var nonce: String
    public var ciphertext: String

    public init(
        version: Int = 1,
        vaultId: String,
        clipId: String,
        updatedAt: Int64,
        operation: EnvelopeOperation,
        nonce: String,
        ciphertext: String
    ) {
        self.version = version
        self.vaultId = vaultId
        self.clipId = clipId
        self.updatedAt = updatedAt
        self.operation = operation
        self.nonce = nonce
        self.ciphertext = ciphertext
    }

    public var metadata: EnvelopeMetadata {
        EnvelopeMetadata(vaultId: vaultId, clipId: clipId, updatedAt: updatedAt, operation: operation)
    }

    public func replacing(updatedAt: Int64) -> Self {
        var copy = self
        copy.updatedAt = updatedAt
        return copy
    }
}

public enum ClipboardConflictResolver {
    public static func resolve(local: ClipboardClip, remote: ClipboardClip) -> ClipboardClip {
        precondition(local.id == remote.id)
        if remote.updatedAt > local.updatedAt { return remote }
        if remote.updatedAt < local.updatedAt { return local }
        if local.deletedAt == nil, remote.deletedAt != nil { return remote }
        if remote.deletedAt == nil, local.deletedAt != nil { return local }
        return remote.sourceDeviceId > local.sourceDeviceId ? remote : local
    }
}

public struct SyncCredentials: Codable, Equatable, Sendable {
    public var vaultId: String
    public var deviceId: String
    public var token: String
    public var groupKey: Data
    public var cursor: String?

    public init(vaultId: String, deviceId: String, token: String, groupKey: Data, cursor: String? = nil) {
        precondition(groupKey.count == 32)
        self.vaultId = vaultId
        self.deviceId = deviceId
        self.token = token
        self.groupKey = groupKey
        self.cursor = cursor
    }
}
