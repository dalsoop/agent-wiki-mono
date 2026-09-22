public struct GameUIHitShape: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Hashable, Sendable {
        case rectangle
        case polygon
    }

    public let kind: Kind
    public let points: [GameUIPoint]

    public init(kind: Kind, points: [GameUIPoint] = []) {
        self.kind = kind
        self.points = points
    }
}

public struct GameUIInteraction: Codable, Hashable, Sendable {
    public let instanceID: String
    public let actionID: String
    public let hitShape: GameUIHitShape
    public let accessibilityLabel: String

    public init(
        instanceID: String,
        actionID: String,
        hitShape: GameUIHitShape,
        accessibilityLabel: String
    ) {
        self.instanceID = instanceID
        self.actionID = actionID
        self.hitShape = hitShape
        self.accessibilityLabel = accessibilityLabel
    }
}
