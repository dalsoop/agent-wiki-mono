import XCTest
@testable import PreviewEngineKit

final class PreviewEngineKitTests: XCTestCase {
    func testFormatDetectorExtensions() {
        XCTAssertEqual(FormatDetector.detect(url: URL(fileURLWithPath: "sample.hwpx")), .hwpx)
        XCTAssertEqual(FormatDetector.detect(url: URL(fileURLWithPath: "data.xlsx")), .xlsx)
        XCTAssertEqual(FormatDetector.detect(url: URL(fileURLWithPath: "document.pdf")), .pdf)
        XCTAssertEqual(FormatDetector.detect(url: URL(fileURLWithPath: "diagram.mmd")), .mermaid)
        XCTAssertEqual(FormatDetector.detect(url: URL(fileURLWithPath: "diagram.mermaid")), .mermaid)
        XCTAssertEqual(FormatDetector.detect(url: URL(fileURLWithPath: "image.png")), .image)
        XCTAssertEqual(FormatDetector.detect(url: URL(fileURLWithPath: "movie.mp4")), .video)
        XCTAssertEqual(FormatDetector.detect(url: URL(fileURLWithPath: "feed.json")), .json)
        XCTAssertEqual(FormatDetector.detect(url: URL(fileURLWithPath: "app.sqlite")), .database)
        XCTAssertEqual(FormatDetector.detect(url: URL(fileURLWithPath: "README.md")), .markdown)
    }

    func testFormatDetectorContent() {
        let mermaidCode = """
        graph TD
            A[Start] --> B[End]
        """
        XCTAssertEqual(FormatDetector.detect(content: mermaidCode), .mermaid)

        let jsonCode = """
        {"name": "Gujo", "count": 42}
        """
        XCTAssertEqual(FormatDetector.detect(content: jsonCode), .json)
    }

    func testPreviewDocumentMetadataInspect() {
        let tempURL = URL(fileURLWithPath: "/tmp/test_inspect.json")
        let meta = PreviewDocumentMetadata.inspect(url: tempURL)
        XCTAssertEqual(meta.format, "json")
        XCTAssertEqual(meta.properties["fileName"], "test_inspect.json")
    }
}
