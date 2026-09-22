import Foundation

/// DocBlock 배열에서 HWPX section0.xml 을 생성한다.
enum SectionBuilder {
    static func build(blocks: [DocBlock]) -> String {
        var body = ""
        for block in blocks {
            switch block {
            case .heading(let level, let text):
                let styleID = headingStyle(level: level)
                body += wrapParagraph(text: escapeXML(text), styleID: styleID, bold: level <= 2)
            case .paragraph(let runs):
                body += buildParagraph(runs: runs)
            case .bullet(let items):
                for item in items {
                    body += wrapParagraph(text: "- \(escapeXML(item))", styleID: "0", bold: false)
                }
            case .table(let rows, let widthsPercent):
                body += buildTable(rows: rows, widthsPercent: widthsPercent)
            case .pageBreak:
                body += pageBreakXML()
            case .image:
                body += wrapParagraph(text: "[image]", styleID: "0", bold: false)
            }
        }

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <hp:sec xmlns:hp="\(HwpxNamespaces.paragraph)" \
        xmlns:hp1="\(HwpxNamespaces.core)" \
        xmlns:hp2="\(HwpxNamespaces.head)">
        <hp:subList>
        \(body)
        </hp:subList>
        </hp:sec>
        """
    }

    private static func headingStyle(level: Int) -> String {
        switch level {
        case 1: return "1"
        case 2: return "2"
        case 3: return "3"
        default: return "0"
        }
    }

    private static func wrapParagraph(text: String, styleID: String, bold: Bool) -> String {
        let charPr = bold ? "<hp:charPr><hp:bold/></hp:charPr>" : ""
        return """
        <hp:p>
        <hp:paraPr styleIDRef="\(styleID)"/>
        <hp:run>\(charPr)<hp:t>\(text)</hp:t></hp:run>
        </hp:p>
        """
    }

    private static func buildParagraph(runs: [DocBlock.Run]) -> String {
        var runXML = ""
        for run in runs {
            let charPr = run.bold ? "<hp:charPr><hp:bold/></hp:charPr>" : ""
            runXML += "<hp:run>\(charPr)<hp:t>\(escapeXML(run.text))</hp:t></hp:run>"
        }
        return """
        <hp:p>
        <hp:paraPr styleIDRef="0"/>
        \(runXML)
        </hp:p>
        """
    }

    private static func buildTable(rows: [[DocBlock.Cell]], widthsPercent: [Int]) -> String {
        let rowCount = rows.count
        let colCount = widthsPercent.count
        guard rowCount > 0, colCount > 0 else { return "" }

        let pageWidthHMU = 42520
        let colWidths = widthsPercent.map { $0 * pageWidthHMU / 100 }

        var cellzoneXML = ""
        for (r, row) in rows.enumerated() {
            var c = 0
            for cell in row {
                let span = min(cell.colspan, colCount - c)
                let w = colWidths[c..<min(c + span, colCount)].reduce(0, +)
                cellzoneXML += "<hp:cellzone col=\"\(c)\" row=\"\(r)\" colSpan=\"\(span)\" rowSpan=\"1\" width=\"\(w)\" height=\"1000\"/>"
                c += span
            }
        }

        var bodyXML = ""
        for (r, row) in rows.enumerated() {
            var rowCells = ""
            var c = 0
            for cell in row {
                let span = min(cell.colspan, colCount - c)
                let w = colWidths[c..<min(c + span, colCount)].reduce(0, +)
                rowCells += """
                <hp:tc>
                <hp:cellAddr colAddr="\(c)" rowAddr="\(r)"/>
                <hp:cellSpan colSpan="\(span)" rowSpan="1"/>
                <hp:cellSz width="\(w)" height="1000"/>
                <hp:subList>
                <hp:p><hp:paraPr styleIDRef="0"/><hp:run><hp:t>\(escapeXML(cell.text))</hp:t></hp:run></hp:p>
                </hp:subList>
                </hp:tc>
                """
                c += span
            }
            bodyXML += "<hp:tr>\(rowCells)</hp:tr>"
        }

        return """
        <hp:tbl rowCnt="\(rowCount)" colCnt="\(colCount)">
        <hp:cellzone-list>
        \(cellzoneXML)
        </hp:cellzone-list>
        \(bodyXML)
        </hp:tbl>
        """
    }

    private static func pageBreakXML() -> String {
        """
        <hp:p>
        <hp:paraPr styleIDRef="0"/>
        <hp:run><hp:ctrl char="page"/></hp:run>
        </hp:p>
        """
    }

    private static func escapeXML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
