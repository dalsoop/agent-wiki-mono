import Foundation

public struct DocumentSlotSpec: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let title: String
    public let isRequired: Bool
    public let acceptedExtensions: [String]

    public init(
        id: String,
        title: String,
        isRequired: Bool = true,
        acceptedExtensions: [String] = ["pdf", "png", "jpg", "hwp"]
    ) {
        self.id = id
        self.title = title
        self.isRequired = isRequired
        self.acceptedExtensions = acceptedExtensions
    }
}
