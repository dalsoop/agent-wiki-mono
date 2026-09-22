import Foundation
import ImageIO
import CoreGraphics

public enum GenerativeImageMetaIO: Sendable {
    public static let supportedExtensions = ["jpg", "jpeg", "png", "tif", "tiff", "heic", "heif"]

    public static func supports(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    public static func write(meta: GenerativeImageMeta, to fileURL: URL) throws {
        guard supports(fileURL) else {
            throw GenerativeImageMetaError.unsupportedFormat(fileURL.pathExtension)
        }
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
              CGImageSourceGetCount(source) > 0 else {
            throw GenerativeImageMetaError.cannotOpen(fileURL.path)
        }
        let type = CGImageSourceGetType(source) ?? uti(for: fileURL) as CFString
        let temp = fileURL.deletingLastPathComponent()
            .appendingPathComponent(".\(fileURL.lastPathComponent).gmeta-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temp) }
        guard let dest = CGImageDestinationCreateWithURL(temp as CFURL, type, 1, nil) else {
            throw GenerativeImageMetaError.writeFailed(fileURL.path)
        }
        var options: [CFString: Any] = properties(from: meta)
        if let xmp = makeXMP(from: meta) {
            options[kCGImageDestinationMetadata] = xmp
            options[kCGImageDestinationMergeMetadata] = true
        }
        CGImageDestinationAddImageFromSource(dest, source, 0, options as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            throw GenerativeImageMetaError.writeFailed(fileURL.path)
        }
        try replace(fileURL, with: temp)
    }

    public static func read(from fileURL: URL) -> GenerativeImageMeta? {
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else { return nil }
        if let fromXMP = readXMP(source) { return fromXMP }
        if let fromEXIF = readEXIFFallback(source) { return fromEXIF }
        return nil
    }

    public static func requirePromptAndSystem(at fileURL: URL, prompt: String) throws {
        guard supports(fileURL) else {
            throw GenerativeImageMetaError.unsupportedFormat(fileURL.pathExtension)
        }
        guard let meta = read(from: fileURL) else {
            throw GenerativeImageMetaError.missingMetadata
        }
        if meta.systemUsed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw GenerativeImageMetaError.missingSystem
        }
        let expected = normalize(prompt)
        let haystack = normalize([meta.prompt, meta.systemUsed].joined(separator: "\n"))
        guard !expected.isEmpty, haystack.contains(expected) else {
            throw GenerativeImageMetaError.missingPrompt
        }
    }

    public static func writeMinimalJPEG(to url: URL) throws {
        let width = 8
        let height = 8
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else {
            throw GenerativeImageMetaError.writeFailed(url.path)
        }
        context.setFillColor(red: 0.2, green: 0.3, blue: 0.8, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage(),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil)
        else {
            throw GenerativeImageMetaError.writeFailed(url.path)
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw GenerativeImageMetaError.writeFailed(url.path)
        }
    }

    private static func makeXMP(from meta: GenerativeImageMeta) -> CGImageMetadata? {
        let metadata = CGImageMetadataCreateMutable()
        let ns = GenerativeImageMeta.xmpNamespace as CFString
        let prefix = GenerativeImageMeta.xmpPrefix as CFString
        func put(_ name: String, _ value: String) {
            guard let tag = CGImageMetadataTagCreate(ns, prefix, name as CFString, .string, value as CFString) else {
                return
            }
            CGImageMetadataSetTagWithPath(metadata, nil, "\(GenerativeImageMeta.xmpPrefix):\(name)" as CFString, tag)
        }
        put("AIPromptInformation", meta.prompt)
        put("AISystemUsed", meta.systemUsed)
        put("DigitalSourceType", meta.digitalSourceType.uri)
        if let writer = meta.promptWriter, !writer.isEmpty {
            put("AIPromptWriterName", writer)
        }
        if let version = meta.systemVersion, !version.isEmpty {
            put("AISystemVersionUsed", version)
        }
        return metadata
    }

    private static func readXMP(_ source: CGImageSource) -> GenerativeImageMeta? {
        guard let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil) else { return nil }
        func text(_ name: String) -> String? {
            let path = "\(GenerativeImageMeta.xmpPrefix):\(name)" as CFString
            guard let tag = CGImageMetadataCopyTagWithPath(metadata, nil, path),
                  let value = CGImageMetadataTagCopyValue(tag) as? String,
                  !value.isEmpty
            else { return nil }
            return value
        }
        guard let prompt = text("AIPromptInformation"), let system = text("AISystemUsed") else {
            return nil
        }
        return GenerativeImageMeta(
            prompt: prompt,
            systemUsed: system,
            systemVersion: text("AISystemVersionUsed"),
            promptWriter: text("AIPromptWriterName"),
            digitalSourceType: IPTCDigitalSourceType.parse(text("DigitalSourceType") ?? "") ?? .trainedAlgorithmicMedia
        )
    }

    private static func readEXIFFallback(_ source: CGImageSource) -> GenerativeImageMeta? {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else { return nil }
        if let exif = props[kCGImagePropertyExifDictionary as String] as? [String: Any],
           let comment = exif[kCGImagePropertyExifUserComment as String] as? String,
           let parsed = decodeComment(comment) {
            return parsed
        }
        var prompt = ""
        var system = ""
        if let tiff = props[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
            prompt = tiff[kCGImagePropertyTIFFImageDescription as String] as? String ?? ""
            system = tiff[kCGImagePropertyTIFFSoftware as String] as? String ?? ""
        }
        if let iptc = props[kCGImagePropertyIPTCDictionary as String] as? [String: Any],
           prompt.isEmpty {
            prompt = iptc[kCGImagePropertyIPTCCaptionAbstract as String] as? String ?? ""
        }
        guard !prompt.isEmpty, !system.isEmpty else { return nil }
        return GenerativeImageMeta(prompt: prompt, systemUsed: system)
    }

    private static func properties(from meta: GenerativeImageMeta) -> [CFString: Any] {
        let comment: String
        if let data = try? JSONEncoder().encode(CommentEnvelope(schema: GenerativeImageMeta.schemaID, meta: meta)),
           let text = String(data: data, encoding: .utf8) {
            comment = text
        } else {
            comment = "prompt=\(meta.prompt)\nmodel=\(meta.systemUsed)"
        }
        return [
            kCGImagePropertyTIFFDictionary: [
                kCGImagePropertyTIFFImageDescription as String: meta.prompt,
                kCGImagePropertyTIFFSoftware as String: meta.systemUsed,
            ],
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifUserComment as String: comment,
            ],
            kCGImagePropertyIPTCDictionary: [
                kCGImagePropertyIPTCCaptionAbstract as String: meta.prompt,
                kCGImagePropertyIPTCSpecialInstructions as String: meta.digitalSourceType.uri,
            ],
        ]
    }

    private static func decodeComment(_ comment: String) -> GenerativeImageMeta? {
        let trimmed = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmed.data(using: .utf8),
           let envelope = try? JSONDecoder().decode(CommentEnvelope.self, from: data) {
            return envelope.meta
        }
        var prompt = ""
        var model = ""
        for line in trimmed.split(whereSeparator: \.isNewline) {
            let text = String(line)
            if text.hasPrefix("prompt=") { prompt = String(text.dropFirst(7)) }
            if text.hasPrefix("model=") { model = String(text.dropFirst(6)) }
        }
        guard !prompt.isEmpty, !model.isEmpty else { return nil }
        return GenerativeImageMeta(prompt: prompt, systemUsed: model)
    }

    private static func replace(_ original: URL, with temp: URL) throws {
        let backup = original.appendingPathExtension("bak-gmeta")
        if FileManager.default.fileExists(atPath: backup.path) {
            try FileManager.default.removeItem(at: backup)
        }
        try FileManager.default.moveItem(at: original, to: backup)
        do {
            try FileManager.default.moveItem(at: temp, to: original)
            try FileManager.default.removeItem(at: backup)
        } catch {
            if FileManager.default.fileExists(atPath: backup.path) {
                do { try FileManager.default.moveItem(at: backup, to: original) } catch { _ = error }
            }
            throw GenerativeImageMetaError.writeFailed(original.path)
        }
    }

    private static func normalize(_ raw: String) -> String {
        raw.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
    }

    private static func uti(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg": return "public.jpeg"
        case "png": return "public.png"
        case "tif", "tiff": return "public.tiff"
        case "heic": return "public.heic"
        case "heif": return "public.heif"
        default: return "public.jpeg"
        }
    }
}

private struct CommentEnvelope: Codable {
    var schema: String
    var meta: GenerativeImageMeta
}
