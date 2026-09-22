public struct GameUIBinding: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Hashable, Sendable {
        case text
        case number
        case meter
        case badge
        case chart
    }

    public let id: String
    public let kind: Kind
    public let key: String
    public let targetInstanceID: String?
    public let frame: GameUIRect?
    public let zIndex: Int?
    public let format: String?

    public init(
        id: String,
        kind: Kind,
        key: String,
        targetInstanceID: String? = nil,
        frame: GameUIRect? = nil,
        zIndex: Int? = nil,
        format: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.key = key
        self.targetInstanceID = targetInstanceID
        self.frame = frame
        self.zIndex = zIndex
        self.format = format
    }
}
