import Foundation

/// `[DocBlock]`에서 HWPX 패키지(zip) `Data`를 생성한다.
/// rhwp 를 쓰지 않고 XML 을 직접 만든다.
public enum HwpxComposer {
    public static func compose(blocks: [DocBlock]) throws -> Data {
        let sectionXML = SectionBuilder.build(blocks: blocks)
        let previewText = previewPlainText(blocks: blocks)

        let entries: [HwpxZipBuilder.Entry] = [
            .init(name: "mimetype", data: Data("application/hwpx+zip".utf8)),
            .init(name: "version.xml", data: Data(HwpxTemplateResources.versionXML.utf8)),
            .init(name: "Contents/header.xml", data: Data(HwpxTemplateResources.headerXML.utf8)),
            .init(name: "Contents/section0.xml", data: Data(sectionXML.utf8)),
            .init(name: "Contents/content.hpf", data: Data(HwpxTemplateResources.contentHPF.utf8)),
            .init(name: "META-INF/container.xml", data: Data(HwpxTemplateResources.containerXML.utf8)),
            .init(name: "Preview/PrvText.txt", data: Data(previewText.utf8)),
        ]

        return HwpxZipBuilder.build(entries: entries)
    }

    private static func previewPlainText(blocks: [DocBlock]) -> String {
        blocks.compactMap { block in
            switch block {
            case .heading(_, let text):
                return text
            case .paragraph(let runs):
                return runs.map(\.text).joined()
            case .bullet(let items):
                return items.map { "- \($0)" }.joined(separator: "\n")
            case .table(let rows, _):
                return rows.map { $0.map(\.text).joined(separator: "\t") }.joined(separator: "\n")
            case .pageBreak:
                return nil
            case .image:
                return nil
            }
        }.joined(separator: "\n")
    }
}
