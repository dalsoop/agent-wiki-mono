public enum GameUIAssetClassification: String, Codable, Hashable, Sendable {
    case referenceOnly = "reference-only"
    case faithfulSource = "faithful-source"
    case component
    case skin
}

public struct GameUIAssetProvenance: Codable, Hashable, Sendable {
    public let classification: GameUIAssetClassification
    public let sourceSHA256: String?
    public let generator: String?
    public let version: String?

    public init(
        classification: GameUIAssetClassification,
        sourceSHA256: String? = nil,
        generator: String? = nil,
        version: String? = nil
    ) {
        self.classification = classification
        self.sourceSHA256 = sourceSHA256
        self.generator = generator
        self.version = version
    }
}

public struct GameUIAsset: Codable, Hashable, Sendable {
    public let path: String
    public let sha256: String
    public let bakedDynamicContent: Bool?
    public let provenance: GameUIAssetProvenance

    public init(
        path: String,
        sha256: String,
        bakedDynamicContent: Bool? = nil,
        provenance: GameUIAssetProvenance
    ) {
        self.path = path
        self.sha256 = sha256
        self.bakedDynamicContent = bakedDynamicContent
        self.provenance = provenance
    }
}
