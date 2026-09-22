public struct GameUIScreenManifest: Codable, Hashable, Sendable {
    public let schemaVersion: Int
    public let id: String
    public let canvas: GameUICanvas
    public let components: [GameUIComponent]
    public let instances: [GameUIInstance]
    public let bindings: [GameUIBinding]
    public let interactions: [GameUIInteraction]

    public init(
        schemaVersion: Int,
        id: String,
        canvas: GameUICanvas,
        components: [GameUIComponent],
        instances: [GameUIInstance],
        bindings: [GameUIBinding],
        interactions: [GameUIInteraction]
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.canvas = canvas
        self.components = components
        self.instances = instances
        self.bindings = bindings
        self.interactions = interactions
    }
}
