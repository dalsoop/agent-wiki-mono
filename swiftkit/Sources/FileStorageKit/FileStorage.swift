import Foundation

/// Codable 값을 JSON 파일로 읽고 쓰는 최소 저장소.
///
/// ```swift
/// let store = FileStorage<Config>(url: configURL)
/// try store.save(config)
/// let loaded = try store.load()
/// ```
public struct FileStorage<T: Codable>: Sendable {
    public let url: URL
    private let pretty: Bool
    private let createDirectories: Bool

    public init(url: URL, pretty: Bool = false, createDirectories: Bool = true) {
        self.url = url
        self.pretty = pretty
        self.createDirectories = createDirectories
    }

    public func load() throws -> T {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(T.self, from: data)
    }

    public func loadOrDefault(_ fallback: T) -> T {
        (try? load()) ?? fallback
    }

    public func save(_ value: T) throws {
        if createDirectories {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        }
        let encoder = JSONEncoder()
        if pretty { encoder.outputFormatting = [.prettyPrinted, .sortedKeys] }
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)
    }

    public func delete() throws {
        try FileManager.default.removeItem(at: url)
    }

    public func exists() -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }
}
