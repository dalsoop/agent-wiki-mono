import Foundation

/// IPTC NewsCodes Digital Source Type.
/// http://cv.iptc.org/newscodes/digitalsourcetype/
public enum IPTCDigitalSourceType: String, Codable, Sendable, Equatable {
    case trainedAlgorithmicMedia
    case compositeWithTrainedAlgorithmicMedia
    case algorithmicMedia

    public var uri: String {
        "http://cv.iptc.org/newscodes/digitalsourcetype/\(rawValue)"
    }

    public static func parse(_ raw: String) -> IPTCDigitalSourceType? {
        if let direct = IPTCDigitalSourceType(rawValue: raw) { return direct }
        if let last = raw.split(separator: "/").last {
            return IPTCDigitalSourceType(rawValue: String(last))
        }
        return nil
    }
}

/// IPTC Photo Metadata Standard 2025.1 — Extension 1.9 AI properties.
/// XMP: Iptc4xmpExt:AIPromptInformation / AIPromptWriterName / AISystemUsed / AISystemVersionUsed
/// plus DigitalSourceType = trainedAlgorithmicMedia for fully generated stills.
public struct GenerativeImageMeta: Codable, Equatable, Sendable {
    public static let schemaID = "iptc-photometadata-2025.1"
    public static let xmpNamespace = "http://iptc.org/std/Iptc4xmpExt/2008-02-29/"
    public static let xmpPrefix = "Iptc4xmpExt"

    public var prompt: String
    public var promptWriter: String?
    public var systemUsed: String
    public var systemVersion: String?
    public var digitalSourceType: IPTCDigitalSourceType

    public init(
        prompt: String,
        systemUsed: String,
        systemVersion: String? = nil,
        promptWriter: String? = nil,
        digitalSourceType: IPTCDigitalSourceType = .trainedAlgorithmicMedia
    ) {
        self.prompt = prompt
        self.promptWriter = promptWriter
        self.systemUsed = systemUsed
        self.systemVersion = systemVersion
        self.digitalSourceType = digitalSourceType
    }
}

public enum GenerativeImageMetaError: Error, Equatable, CustomStringConvertible, Sendable {
    case unsupportedFormat(String)
    case cannotOpen(String)
    case writeFailed(String)
    case missingMetadata
    case missingPrompt
    case missingSystem

    public var description: String {
        switch self {
        case .unsupportedFormat(let ext): "EXIF/XMP를 심을 수 없는 형식입니다: \(ext)"
        case .cannotOpen(let path): "이미지를 열지 못했습니다: \(path)"
        case .writeFailed(let path): "생성 메타 기록에 실패했습니다: \(path)"
        case .missingMetadata: "IPTC/EXIF 생성 메타가 없습니다"
        case .missingPrompt: "메타에 프롬프트(AIPromptInformation)가 없습니다"
        case .missingSystem: "메타에 모델(AISystemUsed)이 없습니다"
        }
    }
}
