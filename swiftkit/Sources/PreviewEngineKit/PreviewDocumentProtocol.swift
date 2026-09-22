import Foundation

// MARK: - L2 Domain Render Driver Protocols

/// 모든 미리보기 가능한 문서 모델의 공통 기본 프로토콜
public protocol PreviewDocument: Sendable {
    var id: UUID { get }
    var fileURL: URL? { get }
    var title: String { get }
    var formatKind: PreviewFormatKind { get }
    var byteSize: Int64 { get }
}

/// 1. 페이지 분할 문서 렌더러 프로토콜 (HWPX, PDF, PPTX 등)
public protocol PaginatedDocumentProvider: PreviewDocument {
    var pageCount: Int { get }
    func pageTitle(at index: Int) -> String?
    func outlineNodes() -> [PreviewOutlineNode]
}

/// 2. 2D 표/스프레드시트 렌더러 프로토콜 (XLSX, CSV, SQLite 등)
public protocol TabularGridProvider: PreviewDocument {
    var sheetNames: [String] { get }
    var currentSheetIndex: Int { get set }
    var rowCount: Int { get }
    var columnCount: Int { get }
    func headerTitle(column: Int) -> String
    func cellValue(row: Int, column: Int) -> String
}

/// 3. 무한 줌/패닝 벡터 캔버스 렌더러 프로토콜 (Mermaid, SVG, 다이어그램 등)
public protocol VectorCanvasProvider: PreviewDocument {
    var sourceCode: String { get }
    var naturalSize: CGSize { get }
    func renderSVGString() async throws -> String
}

/// 4. 계층형 아웃라인/트리 렌더러 프로토콜 (JSON, XML, AST 등)
public protocol HierarchicalTreeProvider: PreviewDocument {
    var rootNodes: [PreviewOutlineNode] { get }
    var rawText: String { get }
}

/// 5. 연속 미디어 렌더러 프로토콜 (비디오, 오디오 등)
public protocol ContinuousMediaProvider: PreviewDocument {
    var durationSeconds: Double { get }
    var tracksCount: Int { get }
    var isAudioOnly: Bool { get }
}

/// 6. 비트맵/래스터 이미지 렌더러 프로토콜 (PNG, JPG, PSD, RAW 등)
public protocol BitmapImageProvider: PreviewDocument {
    var pixelWidth: Int { get }
    var pixelHeight: Int { get }
    var colorSpaceName: String { get }
    var layersCount: Int { get }
}

// MARK: - L3 Capability Traits (옵트인 역량 인터페이스)

public protocol SearchablePreviewCapability {
    func search(query: String) async -> [PreviewSearchResult]
}

public protocol ExportablePreviewCapability {
    var supportedExportFormats: [String] { get }
    func export(to format: String, destinationURL: URL) async throws
}

public protocol EditablePreviewCapability {
    var canEditInline: Bool { get }
    func applyEdit(change: PreviewChangeOperation) throws
}

// MARK: - 공통 DTO 모델

public struct PreviewOutlineNode: Identifiable, Sendable, Codable {
    public let id: String
    public let title: String
    public let detail: String?
    public let level: Int
    public let children: [PreviewOutlineNode]

    public init(id: String, title: String, detail: String? = nil, level: Int = 0, children: [PreviewOutlineNode] = []) {
        self.id = id
        self.title = title
        self.detail = detail
        self.level = level
        self.children = children
    }
}

public struct PreviewSearchResult: Identifiable, Sendable, Codable {
    public let id: String
    public let snippet: String
    public let locationHint: String
    public let pageOrRowIndex: Int

    public init(id: String, snippet: String, locationHint: String, pageOrRowIndex: Int) {
        self.id = id
        self.snippet = snippet
        self.locationHint = locationHint
        self.pageOrRowIndex = pageOrRowIndex
    }
}

public enum PreviewChangeOperation: Sendable {
    case replaceText(range: Range<String.Index>, replacement: String)
    case updateCell(row: Int, column: Int, value: String)
}
