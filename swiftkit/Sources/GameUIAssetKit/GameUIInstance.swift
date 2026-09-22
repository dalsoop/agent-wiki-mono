public struct GameUIInstance: Codable, Hashable, Sendable {
    public let id: String
    public let componentID: String
    public let frame: GameUIRect
    public let anchor: GameUIAnchor
    public let zIndex: Int
    public let visibilityBinding: String?
    public let stateBinding: String?
    public let allowsOverflow: Bool

    public init(
        id: String,
        componentID: String,
        frame: GameUIRect,
        anchor: GameUIAnchor,
        zIndex: Int,
        visibilityBinding: String? = nil,
        stateBinding: String? = nil,
        allowsOverflow: Bool = false
    ) {
        self.id = id
        self.componentID = componentID
        self.frame = frame
        self.anchor = anchor
        self.zIndex = zIndex
        self.visibilityBinding = visibilityBinding
        self.stateBinding = stateBinding
        self.allowsOverflow = allowsOverflow
    }
}
