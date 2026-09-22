import Foundation
import CryptoKit
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

public enum AssetStoreError: Error, LocalizedError, Equatable {
    case metadataNotFound(String)
    case assetNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .metadataNotFound(let hash):
            return "Metadata sidecar for hash \(hash) not found."
        case .assetNotFound(let hash):
            return "Asset file for hash \(hash) not found."
        }
    }
}

public struct AssetStore: Sendable {
    public let rootDirectory: URL

    public init(rootDirectory: URL = URL(fileURLWithPath: "objects")) {
        self.rootDirectory = rootDirectory
    }

    public func store(fileURL: URL, media: MediaMetadata? = nil) throws -> AssetObject {
        if !FileManager.default.fileExists(atPath: rootDirectory.path) {
            try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        }

        let data = try Data(contentsOf: fileURL)
        let digest = SHA256.hash(data: data)
        let hash = digest.map { String(format: "%02x", $0) }.joined()

        let sidecarURL = rootDirectory.appendingPathComponent("\(hash).json")
        if FileManager.default.fileExists(atPath: sidecarURL.path) {
            return try metadata(hash: hash)
        }

        let ext = fileURL.pathExtension
        let targetFilename = ext.isEmpty ? hash : "\(hash).\(ext)"
        let targetURL = rootDirectory.appendingPathComponent(targetFilename)

        if !FileManager.default.fileExists(atPath: targetURL.path) {
            try FileManager.default.copyItem(at: fileURL, to: targetURL)
        }

        let mime = detectMIMEType(for: fileURL)
        let asset = AssetObject(
            hash: hash,
            sizeBytes: Int64(data.count),
            mime: mime,
            createdAt: Date(),
            originalName: fileURL.lastPathComponent,
            media: media
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let jsonData = try encoder.encode(asset)
        try jsonData.write(to: sidecarURL, options: .atomic)

        return try metadata(hash: hash)
    }

    public func lookup(hash: String) -> URL? {
        guard FileManager.default.fileExists(atPath: rootDirectory.path) else { return nil }
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        for item in contents {
            if item.pathExtension.lowercased() == "json" {
                continue
            }
            let filename = item.lastPathComponent
            if filename == hash || filename.hasPrefix("\(hash).") {
                return item
            }
        }
        return nil
    }

    public func metadata(hash: String) throws -> AssetObject {
        let sidecarURL = rootDirectory.appendingPathComponent("\(hash).json")
        guard FileManager.default.fileExists(atPath: sidecarURL.path) else {
            throw AssetStoreError.metadataNotFound(hash)
        }
        let data = try Data(contentsOf: sidecarURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AssetObject.self, from: data)
    }

    public func exists(hash: String) -> Bool {
        return lookup(hash: hash) != nil
    }

    private func detectMIMEType(for url: URL) -> String {
        let ext = url.pathExtension
        guard !ext.isEmpty else {
            return "application/octet-stream"
        }
        #if canImport(UniformTypeIdentifiers)
        if let utType = UTType(filenameExtension: ext),
           let preferredMime = utType.preferredMIMEType {
            return preferredMime
        }
        #endif
        return "application/octet-stream"
    }
}
