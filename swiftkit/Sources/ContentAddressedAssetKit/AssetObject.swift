import Foundation

public struct MediaMetadata: Codable, Sendable, Equatable {
    public let durationSeconds: Double?
    public let peer: String?
    public let extra: [String: String]?

    public init(
        durationSeconds: Double? = nil,
        peer: String? = nil,
        extra: [String: String]? = nil
    ) {
        self.durationSeconds = durationSeconds
        self.peer = peer
        self.extra = extra
    }
}

public struct AssetObject: Codable, Sendable, Equatable, Identifiable {
    public var id: String { hash }

    public let hash: String
    public let sizeBytes: Int64
    public let mime: String
    public let createdAt: Date
    public let originalName: String
    public let media: MediaMetadata?

    public init(
        hash: String,
        sizeBytes: Int64,
        mime: String,
        createdAt: Date,
        originalName: String,
        media: MediaMetadata? = nil
    ) {
        self.hash = hash
        self.sizeBytes = sizeBytes
        self.mime = mime
        self.createdAt = createdAt
        self.originalName = originalName
        self.media = media
    }
}
