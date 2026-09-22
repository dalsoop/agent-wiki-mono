import Foundation

public struct GameEntityID: RawRepresentable, Codable, Hashable, Sendable,
    Comparable, ExpressibleByStringLiteral, CustomStringConvertible {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        rawValue = value
    }

    public static func random(prefix: String? = nil) -> Self {
        let value = UUID().uuidString.lowercased()
        return Self(prefix.map { "\($0).\(value)" } ?? value)
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var description: String { rawValue }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct GameEntityRecord: Codable, Equatable, Sendable {
    public var id: GameEntityID
    public var parentID: GameEntityID?
    public var tags: Set<String>

    public init(
        id: GameEntityID,
        parentID: GameEntityID? = nil,
        tags: Set<String> = []
    ) {
        self.id = id
        self.parentID = parentID
        self.tags = tags
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case parentID
        case tags
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(GameEntityID.self, forKey: .id)
        parentID = try container.decodeIfPresent(GameEntityID.self, forKey: .parentID)
        let decodedTags = try container.decode([String].self, forKey: .tags)
        tags = Set(decodedTags)
        guard tags.count == decodedTags.count else {
            throw DecodingError.dataCorruptedError(
                forKey: .tags,
                in: container,
                debugDescription: "entity tags must be unique"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(parentID, forKey: .parentID)
        try container.encode(tags.sorted(), forKey: .tags)
    }
}
