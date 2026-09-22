import Foundation

/// mp4 등 EXIF 가 없는 생성 미디어용 sidecar.
/// 파일 `clip.mp4` 옆에 `clip.gmeta.json`.
public struct GenerativeMediaSidecar: Codable, Equatable, Sendable {
    public static let schemaID = "ranode.generative-media-sidecar/1"
    public static let fileExtension = "gmeta.json"

    public var schema: String
    public var prompt: String
    public var systemUsed: String
    public var provider: String?
    public var aspect: String?
    public var durationSeconds: Int?
    public var width: Int?
    public var height: Int?

    public init(
        prompt: String,
        systemUsed: String,
        provider: String? = nil,
        aspect: String? = nil,
        durationSeconds: Int? = nil,
        width: Int? = nil,
        height: Int? = nil,
        schema: String = GenerativeMediaSidecar.schemaID
    ) {
        self.schema = schema
        self.prompt = prompt
        self.systemUsed = systemUsed
        self.provider = provider
        self.aspect = aspect
        self.durationSeconds = durationSeconds
        self.width = width
        self.height = height
    }

    public static func sidecarURL(for mediaURL: URL) -> URL {
        mediaURL.deletingPathExtension().appendingPathExtension(fileExtension)
    }

    public static func write(_ meta: GenerativeMediaSidecar, nextTo mediaURL: URL) throws {
        guard !meta.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GenerativeImageMetaError.missingPrompt
        }
        guard !meta.systemUsed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GenerativeImageMetaError.missingSystem
        }
        var copy = meta
        copy.schema = schemaID
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(copy)
        try data.write(to: sidecarURL(for: mediaURL), options: .atomic)
    }

    public static func read(nextTo mediaURL: URL) -> GenerativeMediaSidecar? {
        let url = sidecarURL(for: mediaURL)
        guard let data = try? Data(contentsOf: url),
              let meta = try? JSONDecoder().decode(GenerativeMediaSidecar.self, from: data),
              meta.schema == schemaID
        else { return nil }
        return meta
    }

    public static func requirePromptAndSystem(at mediaURL: URL, prompt: String, model: String) throws {
        guard let meta = read(nextTo: mediaURL) else {
            throw GenerativeImageMetaError.missingMetadata
        }
        if meta.systemUsed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw GenerativeImageMetaError.missingSystem
        }
        if meta.systemUsed != model {
            throw GenerativeImageMetaError.missingSystem
        }
        let expected = normalize(prompt)
        let haystack = normalize(meta.prompt)
        guard !expected.isEmpty, haystack.contains(expected) else {
            throw GenerativeImageMetaError.missingPrompt
        }
    }

    private static func normalize(_ raw: String) -> String {
        raw.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
    }
}
