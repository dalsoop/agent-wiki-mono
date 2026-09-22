import Foundation

/// 미리보기 대상 문서의 지원 포맷 카테고리
public enum PreviewFormatKind: String, Sendable, Codable, CaseIterable {
    case hwpx
    case xlsx
    case pdf
    case pptx
    case mermaid
    case image
    case video
    case json
    case database
    case markdown
    case unknown

    public var displayName: String {
        switch self {
        case .hwpx: return "한글 문서 (HWPX)"
        case .xlsx: return "스프레드시트 (XLSX)"
        case .pdf: return "PDF 문서"
        case .pptx: return "프레젠테이션 (PPTX)"
        case .mermaid: return "다이어그램 (Mermaid)"
        case .image: return "이미지"
        case .video: return "비디오/미디어"
        case .json: return "JSON / 구조화 데이터"
        case .database: return "SQLite 데이터베이스"
        case .markdown: return "마크다운 문서"
        case .unknown: return "알 수 없는 포맷"
        }
    }
}

/// 포맷 자동 판별기 (확장자, 파일 헤더/매직 넘버 기반)
public struct FormatDetector: Sendable {
    public init() {}

    public static func detect(url: URL) -> PreviewFormatKind {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "hwpx", "hwp":
            return .hwpx
        case "xlsx", "xlsm", "xls", "csv", "tsv":
            return .xlsx
        case "pdf":
            return .pdf
        case "pptx", "ppt":
            return .pptx
        case "mmd", "mermaid":
            return .mermaid
        case "png", "jpg", "jpeg", "webp", "heic", "tiff", "tif", "gif", "svg", "bmp", "ico", "icns", "psd", "cr2", "cr3", "nef", "arw", "dng":
            return .image
        case "mp4", "mov", "m4v", "mkv", "webm", "avi":
            return .video
        case "json", "jsonl":
            return .json
        case "sqlite", "sqlite3", "db":
            return .database
        case "md", "markdown":
            return .markdown
        default:
            return detectByContentOrFallback(url: url)
        }
    }

    public static func detect(content: String) -> PreviewFormatKind {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("graph ") || trimmed.hasPrefix("flowchart ") ||
            trimmed.hasPrefix("sequenceDiagram") || trimmed.hasPrefix("classDiagram") ||
            trimmed.hasPrefix("erDiagram") || trimmed.hasPrefix("stateDiagram") {
            return .mermaid
        }
        if (trimmed.hasPrefix("{") && trimmed.hasSuffix("}")) ||
            (trimmed.hasPrefix("[") && trimmed.hasSuffix("]")) {
            return .json
        }
        return .unknown
    }

    private static func detectByContentOrFallback(url: URL) -> PreviewFormatKind {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return .unknown
        }
        defer { try? handle.close() }
        let headerData = (try? handle.read(upToCount: 32)) ?? Data()
        guard headerData.count >= 4 else { return .unknown }

        // SQLite 매직 넘버: "SQLite format 3\0"
        if headerData.starts(with: [0x53, 0x51, 0x4C, 0x69, 0x74, 0x65, 0x20, 0x66, 0x6F, 0x72, 0x6D, 0x61, 0x74, 0x20, 0x33, 0x00]) {
            return .database
        }
        // PDF 매직 넘버: "%PDF-"
        if headerData.starts(with: [0x25, 0x50, 0x44, 0x46, 0x2D]) {
            return .pdf
        }
        // PNG 매직 넘버
        if headerData.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) {
            return .image
        }
        // JPEG 매직 넘버
        if headerData.starts(with: [0xFF, 0xD8, 0xFF]) {
            return .image
        }

        return .unknown
    }
}
