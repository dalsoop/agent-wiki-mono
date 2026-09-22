import Foundation

/// CLI `document-preview-inspector inspect <file> --json` 명령이 반환하는 통합 메타데이터 모델
public struct PreviewDocumentMetadata: Sendable, Codable {
    public let format: String
    public let formatDisplayName: String
    public let filePath: String
    public let byteSize: Int64
    public let summary: String
    public let properties: [String: String]
    public let outline: [PreviewOutlineNode]

    public init(
        format: String,
        formatDisplayName: String,
        filePath: String,
        byteSize: Int64,
        summary: String,
        properties: [String: String],
        outline: [PreviewOutlineNode] = []
    ) {
        self.format = format
        self.formatDisplayName = formatDisplayName
        self.filePath = filePath
        self.byteSize = byteSize
        self.summary = summary
        self.properties = properties
        self.outline = outline
    }

    /// 파일 URL로부터 빠른 정적 메타데이터 추출
    public static func inspect(url: URL) -> PreviewDocumentMetadata {
        let format = FormatDetector.detect(url: url)
        let byteSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0

        var props: [String: String] = [:]
        props["fileName"] = url.lastPathComponent
        props["pathExtension"] = url.pathExtension

        let summary = "포맷: \(format.displayName), 크기: \(byteSize) 바이트"

        return PreviewDocumentMetadata(
            format: format.rawValue,
            formatDisplayName: format.displayName,
            filePath: url.path,
            byteSize: byteSize,
            summary: summary,
            properties: props,
            outline: []
        )
    }
}
