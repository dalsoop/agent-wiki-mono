import Foundation

public struct StageSpec: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let order: Int
    public let requiredSlotIDs: [String]

    public init(
        id: String,
        name: String,
        order: Int,
        requiredSlotIDs: [String] = []
    ) {
        self.id = id
        self.name = name
        self.order = order
        self.requiredSlotIDs = requiredSlotIDs
    }
}
