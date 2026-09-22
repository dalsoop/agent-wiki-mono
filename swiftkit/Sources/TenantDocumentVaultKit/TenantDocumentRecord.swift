import Foundation

public struct TenantDocumentRecord: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let tenantID: String
    public let kind: TenantDocumentKind
    public let assetHash: String
    public let originalName: String
    public let sizeBytes: Int64
    public let issuedAt: Date
    public let expiresAt: Date?

    public init(
        id: String = UUID().uuidString,
        tenantID: String,
        kind: TenantDocumentKind,
        assetHash: String,
        originalName: String,
        sizeBytes: Int64,
        issuedAt: Date,
        expiresAt: Date?
    ) {
        self.id = id
        self.tenantID = tenantID
        self.kind = kind
        self.assetHash = assetHash
        self.originalName = originalName
        self.sizeBytes = sizeBytes
        self.issuedAt = issuedAt
        self.expiresAt = expiresAt
    }

    public var isExpired: Bool {
        guard let expiresAt else { return false }
        return Date() > expiresAt
    }

    public func daysRemaining(from now: Date = Date()) -> Int? {
        guard let expiresAt else { return nil }
        let calendar = Calendar.current
        let startFrom = calendar.startOfDay(for: now)
        let startExpires = calendar.startOfDay(for: expiresAt)
        let components = calendar.dateComponents([.day], from: startFrom, to: startExpires)
        return components.day
    }
}
