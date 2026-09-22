public struct GameUIComponent: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Hashable, Sendable {
        case image
        case nineSlice = "nine-slice"
        case meterTrack = "meter-track"
        case buttonSkin = "button-skin"
        case panel
        case portraitFrame = "portrait-frame"
    }

    public let id: String
    public let kind: Kind
    public let asset: GameUIAsset?
    public let nineSliceInsets: GameUIEdgeInsets?

    public init(
        id: String,
        kind: Kind,
        asset: GameUIAsset? = nil,
        nineSliceInsets: GameUIEdgeInsets? = nil
    ) {
        self.id = id
        self.kind = kind
        self.asset = asset
        self.nineSliceInsets = nineSliceInsets
    }
}
