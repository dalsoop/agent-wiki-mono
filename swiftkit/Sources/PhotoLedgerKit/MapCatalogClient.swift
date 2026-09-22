import Foundation

public enum PhotoDomainPaths {
    public static var classificationMapFile: URL {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Library/Application Support/PhotoClassificationMap/map.json")
    }

    public static func nfc(_ raw: String) -> String {
        raw.precomposedStringWithCanonicalMapping
    }
}

/// 분류 지도(map.json) 읽기 전용. 칸은 photo-classification-map 소유.
public struct MapCellRef: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var label: String
    public var aliases: [String]

    public init(id: String, label: String, aliases: [String] = []) {
        self.id = id
        self.label = label
        self.aliases = aliases
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        label = try c.decode(String.self, forKey: .label)
        aliases = try c.decodeIfPresent([String].self, forKey: .aliases) ?? []
    }
}

public struct MapPlacementRef: Codable, Sendable, Equatable {
    public var blobId: String
    public var cellId: String

    public init(blobId: String, cellId: String) {
        self.blobId = blobId
        self.cellId = cellId
    }
}

public struct MapSnapshot: Codable, Sendable, Equatable {
    public var cells: [MapCellRef]
    public var placements: [MapPlacementRef]

    public init(cells: [MapCellRef] = [], placements: [MapPlacementRef] = []) {
        self.cells = cells
        self.placements = placements
    }

    public func cell(idOrLabel: String) -> MapCellRef? {
        let key = idOrLabel.precomposedStringWithCanonicalMapping
        for cell in cells {
            if cell.id == key { return cell }
            if cell.id.hasPrefix(key) { return cell }
            if cell.label.precomposedStringWithCanonicalMapping == key { return cell }
            if cell.aliases.contains(key) { return cell }
        }
        return nil
    }

    public func blobIDs(inCell idOrLabel: String) -> Set<String> {
        guard let cell = cell(idOrLabel: idOrLabel) else { return [] }
        return Set(placements.filter { $0.cellId == cell.id }.map(\.blobId))
    }

    public func placementCounts() -> [String: Int] {
        var counts: [String: Int] = [:]
        counts.reserveCapacity(cells.count)
        for row in placements {
            counts[row.cellId, default: 0] += 1
        }
        return counts
    }
}

public struct MapCatalogClient: Sendable {
    public var mapURL: URL

    public init(mapURL: URL = PhotoDomainPaths.classificationMapFile) {
        self.mapURL = mapURL
    }

    public func load() throws -> MapSnapshot {
        guard FileManager.default.fileExists(atPath: mapURL.path) else {
            return MapSnapshot()
        }
        let data = try Data(contentsOf: mapURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(MapSnapshot.self, from: data)
    }
}
