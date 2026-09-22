import Foundation

public struct GameUIIdentityToken: Codable, Equatable, Hashable, Sendable,
    ExpressibleByStringLiteral
{
    public var nodeID: String
    public var repeatedKey: String?

    public init(nodeID: String, repeatedKey: String? = nil) {
        self.nodeID = nodeID
        self.repeatedKey = repeatedKey
    }

    public init(stringLiteral value: String) {
        nodeID = value
        repeatedKey = nil
    }
}

public struct GameUIIdentityPath: Codable, Equatable, Hashable, Sendable,
    ExpressibleByArrayLiteral
{
    public var tokens: [GameUIIdentityToken]

    public init(_ tokens: [GameUIIdentityToken]) {
        self.tokens = tokens
    }

    public init(arrayLiteral elements: GameUIIdentityToken...) {
        tokens = elements
    }

    public func appending(_ token: GameUIIdentityToken) -> Self {
        .init(tokens + [token])
    }
}

public enum GameUICoordinateSpace: String, Codable, Equatable, Sendable {
    case screen
    case world
}

public struct GameUIInteraction: Codable, Equatable, Sendable {
    public var downActionID: String?
    public var upActionID: String?
    public var hoverActionID: String?
    public var capturesPointer: Bool

    public init(
        downActionID: String? = nil,
        upActionID: String? = nil,
        hoverActionID: String? = nil,
        capturesPointer: Bool = false
    ) {
        self.downActionID = downActionID
        self.upActionID = upActionID
        self.hoverActionID = hoverActionID
        self.capturesPointer = capturesPointer
    }
}

public struct GameUIRuntimeNode: Codable, Equatable, Sendable {
    public struct Layout: Equatable, Sendable {
        public var frame: GameUIRect
        public var clipRect: GameUIRect?
        public var coordinateSpace: GameUICoordinateSpace
        public var layerID: String
        public var zIndex: Int

        public init(
            frame: GameUIRect,
            clipRect: GameUIRect? = nil,
            coordinateSpace: GameUICoordinateSpace = .screen,
            layerID: String = "default",
            zIndex: Int = 0
        ) {
            self.frame = frame
            self.clipRect = clipRect
            self.coordinateSpace = coordinateSpace
            self.layerID = layerID
            self.zIndex = zIndex
        }
    }

    public struct Appearance: Equatable, Sendable {
        public var isVisible: Bool
        public var isEnabled: Bool
        public var opacity: Double
        public var blocksLowerLayers: Bool

        public init(
            isVisible: Bool = true,
            isEnabled: Bool = true,
            opacity: Double = 1,
            blocksLowerLayers: Bool = false
        ) {
            self.isVisible = isVisible
            self.isEnabled = isEnabled
            self.opacity = opacity
            self.blocksLowerLayers = blocksLowerLayers
        }
    }

    public var id: String
    public var repeatedKey: String?
    public var frame: GameUIRect
    public var clipRect: GameUIRect?
    public var coordinateSpace: GameUICoordinateSpace
    public var layerID: String
    public var zIndex: Int
    public var isVisible: Bool
    public var isEnabled: Bool
    public var opacity: Double
    public var blocksLowerLayers: Bool
    public var interaction: GameUIInteraction?
    public var children: [Self]

    public init(
        id: String,
        repeatedKey: String? = nil,
        layout: Layout,
        appearance: Appearance = Appearance(),
        interaction: GameUIInteraction? = nil,
        children: [Self] = []
    ) {
        self.id = id
        self.repeatedKey = repeatedKey
        self.frame = layout.frame
        self.clipRect = layout.clipRect
        self.coordinateSpace = layout.coordinateSpace
        self.layerID = layout.layerID
        self.zIndex = layout.zIndex
        self.isVisible = appearance.isVisible
        self.isEnabled = appearance.isEnabled
        self.opacity = appearance.opacity
        self.blocksLowerLayers = appearance.blocksLowerLayers
        self.interaction = interaction
        self.children = children
    }

    public func identityPath(
        forNodeID nodeID: String,
        repeatedKey targetRepeatedKey: String? = nil
    ) -> GameUIIdentityPath? {
        identityPath(
            forNodeID: nodeID,
            repeatedKey: targetRepeatedKey,
            parent: .init([])
        )
    }

    var identityToken: GameUIIdentityToken {
        .init(nodeID: id, repeatedKey: repeatedKey)
    }

    private func identityPath(
        forNodeID nodeID: String,
        repeatedKey targetRepeatedKey: String?,
        parent: GameUIIdentityPath
    ) -> GameUIIdentityPath? {
        let current = parent.appending(identityToken)
        let keyMatches = targetRepeatedKey == nil || repeatedKey == targetRepeatedKey
        if id == nodeID && keyMatches {
            return current
        }
        for child in children {
            if let match = child.identityPath(
                forNodeID: nodeID,
                repeatedKey: targetRepeatedKey,
                parent: current
            ) {
                return match
            }
        }
        return nil
    }
}
