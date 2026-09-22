import Foundation

/// Loads/saves user dependency overlay.
public struct DependencyCatalogStore: Sendable {
    public let path: String

    public init(
        path: String = (NSHomeDirectory() as NSString)
            .appendingPathComponent("Library/Application Support/AppFleetDoctor/dependencies.json")
    ) {
        self.path = path
    }

    public func loadMerged(with builtIn: DependencyCatalog = .builtIn) -> DependencyCatalog {
        guard let data = FileManager.default.contents(atPath: path),
              let overlay = try? JSONDecoder().decode(DependencyCatalog.self, from: data)
        else {
            return builtIn
        }
        return builtIn.merging(overlay: overlay)
    }

    public func save(_ catalog: DependencyCatalog) throws {
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try enc.encode(catalog)
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}
