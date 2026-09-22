import Foundation
import Testing
@testable import HwpxComposeKit

@Suite("HwpxComposeKit")
struct HwpxComposeKitTests {
    private static let sampleMarkdown = """
    # Title

    Hello world.

    - one
    - two

    | A | B |
    |---|---|
    | 1 | 2 |

    ---

    ## Sub
    """

    @Test func markdownParsesHeadingParagraphBullet() {
        let blocks = MarkdownToDocBlocks.convert(Self.sampleMarkdown)
        #expect(blocks.count == 6)
        if case .heading(let level, let text) = blocks[0] {
            #expect(level == 1)
            #expect(text == "Title")
        } else { Issue.record("Expected heading") }
        if case .paragraph(let runs) = blocks[1] {
            #expect(runs.first?.text == "Hello world.")
        } else { Issue.record("Expected paragraph") }
        if case .bullet(let items) = blocks[2] {
            #expect(items == ["one", "two"])
        } else { Issue.record("Expected bullet") }
    }

    @Test func markdownParsesTablePageBreakHeading2() {
        let blocks = MarkdownToDocBlocks.convert(Self.sampleMarkdown)
        if case .table(let rows, _) = blocks[3] {
            #expect(rows.count == 2)
            #expect(rows[0][0].text == "A")
            #expect(rows[1][0].text == "1")
        } else { Issue.record("Expected table") }
        if case .pageBreak = blocks[4] {} else { Issue.record("Expected pageBreak") }
        if case .heading(let level, _) = blocks[5] {
            #expect(level == 2)
        } else { Issue.record("Expected heading 2") }
    }

    @Test func composeProducesValidZip() throws {
        let blocks: [DocBlock] = [
            .heading(level: 1, text: "Test"),
            .paragraph([.init(text: "Hello")]),
        ]
        let data = try HwpxComposer.compose(blocks: blocks)

        #expect(data[0] == 0x50)
        #expect(data[1] == 0x4B)

        let utf8 = String(decoding: data, as: UTF8.self)
        #expect(utf8.contains("application/hwpx+zip"))
        #expect(utf8.contains("Contents/section0.xml"))
        #expect(utf8.contains("Contents/header.xml"))
    }

    @Test func composeTableHasRowColCounts() throws {
        let blocks: [DocBlock] = [
            .table(
                rows: [
                    [.init(text: "A"), .init(text: "B")],
                    [.init(text: "1"), .init(text: "2")],
                ],
                widthsPercent: [50, 50]
            ),
        ]
        let data = try HwpxComposer.compose(blocks: blocks)
        let utf8 = String(decoding: data, as: UTF8.self)
        #expect(utf8.contains("rowCnt=\"2\""))
        #expect(utf8.contains("colCnt=\"2\""))
        #expect(utf8.contains("cellzone"))
    }

    @Test func boldRunsParsed() {
        let md = "This is **bold** text."
        let blocks = MarkdownToDocBlocks.convert(md)
        guard case .paragraph(let runs) = blocks.first else {
            Issue.record("Expected paragraph")
            return
        }
        #expect(runs.count == 3)
        #expect(!runs[0].bold)
        #expect(runs[1].bold)
        #expect(runs[1].text == "bold")
        #expect(!runs[2].bold)
    }

    @Test func sectionBuilderEscapesXML() {
        let blocks: [DocBlock] = [
            .paragraph([.init(text: "a < b & c > d")]),
        ]
        let xml = SectionBuilder.build(blocks: blocks)
        #expect(xml.contains("a &lt; b &amp; c &gt; d"))
    }

    @Test func composeWritesToDisk() throws {
        let blocks = MarkdownToDocBlocks.convert("# Hello\n\nWorld.")
        let data = try HwpxComposer.compose(blocks: blocks)
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID()).hwpx")
        try data.write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let loaded = try Data(contentsOf: tmp)
        #expect(loaded[0] == 0x50)
        #expect(loaded.count == data.count)
    }
}
