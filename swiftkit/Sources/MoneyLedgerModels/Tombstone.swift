import Foundation

/// 삭제된 엔티티를 추적하는 툼스톤 레코드 (양방향 동기화 시 삭제 전파 및 좀비 원장 부활 방지).
public struct TombstoneRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: String { "\(entityType):\(entityID)" }
    public var entityType: String
    public var entityID: String
    public var deletedAt: Date

    public init(entityType: String, entityID: String, deletedAt: Date = Date()) {
        self.entityType = entityType
        self.entityID = entityID
        self.deletedAt = deletedAt
    }
}
