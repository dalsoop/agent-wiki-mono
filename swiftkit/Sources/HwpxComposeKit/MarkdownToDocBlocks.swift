import Foundation

/// 마크다운 부분집합을 `[DocBlock]`으로 변환한다.
/// 지원: `#`/`##`/`###` 헤딩, 빈 줄 구분 문단, `- ` 목록, 파이프 표(`|---|`), `---` 페이지 브레이크.
public enum MarkdownToDocBlocks {
    public static func convert(_ markdown: String) -> [DocBlock] {
        let lines = markdown.components(separatedBy: "\n")
        var blocks: [DocBlock] = []
        var i = 0

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                i += 1
                continue
            }

            if trimmed == "---" {
                blocks.append(.pageBreak)
                i += 1
                continue
            }

            if let heading = parseHeading(trimmed) {
                blocks.append(heading)
                i += 1
                continue
            }

            if trimmed.hasPrefix("- ") {
                var items: [String] = []
                while i < lines.count {
                    let bulletLine = lines[i].trimmingCharacters(in: .whitespaces)
                    guard bulletLine.hasPrefix("- ") else { break }
                    items.append(String(bulletLine.dropFirst(2)))
                    i += 1
                }
                blocks.append(.bullet(items))
                continue
            }

            if trimmed.hasPrefix("|") {
                let (table, consumed) = parseTable(lines: lines, startIndex: i)
                if let table {
                    blocks.append(table)
                }
                i += consumed
                continue
            }

            var paragraphRuns: [DocBlock.Run] = []
            while i < lines.count {
                let pLine = lines[i]
                let pTrimmed = pLine.trimmingCharacters(in: .whitespaces)
                if pTrimmed.isEmpty { break }
                if pTrimmed == "---" { break }
                if pTrimmed.hasPrefix("# ") || pTrimmed.hasPrefix("## ") || pTrimmed.hasPrefix("### ") { break }
                if pTrimmed.hasPrefix("- ") { break }
                if pTrimmed.hasPrefix("|") { break }
                paragraphRuns.append(contentsOf: parseInlineRuns(pTrimmed))
                i += 1
            }
            if !paragraphRuns.isEmpty {
                blocks.append(.paragraph(paragraphRuns))
            }
        }
        return blocks
    }

    private static func parseHeading(_ line: String) -> DocBlock? {
        if line.hasPrefix("### ") {
            return .heading(level: 3, text: String(line.dropFirst(4)))
        }
        if line.hasPrefix("## ") {
            return .heading(level: 2, text: String(line.dropFirst(3)))
        }
        if line.hasPrefix("# ") {
            return .heading(level: 1, text: String(line.dropFirst(2)))
        }
        return nil
    }

    private static func parseInlineRuns(_ text: String) -> [DocBlock.Run] {
        var runs: [DocBlock.Run] = []
        var current = ""
        var bold = false
        var idx = text.startIndex

        while idx < text.endIndex {
            if text[idx...].hasPrefix("**") {
                if !current.isEmpty {
                    runs.append(.init(text: current, bold: bold))
                    current = ""
                }
                bold.toggle()
                idx = text.index(idx, offsetBy: 2)
            } else {
                current.append(text[idx])
                idx = text.index(after: idx)
            }
        }
        if !current.isEmpty {
            runs.append(.init(text: current, bold: bold))
        }
        return runs
    }

    private static func parseTable(lines: [String], startIndex: Int) -> (DocBlock?, Int) {
        var i = startIndex
        var dataRows: [[String]] = []

        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("|") else { break }

            let cells = parsePipeCells(line)

            let isSeparator = cells.allSatisfy { $0.allSatisfy { $0 == "-" || $0 == ":" || $0 == " " } }
            if isSeparator {
                i += 1
                continue
            }

            dataRows.append(cells)
            i += 1
        }

        guard !dataRows.isEmpty else { return (nil, i - startIndex) }

        let colCount = dataRows.map(\.count).max() ?? 1
        let widths = evenWidths(colCount)
        let cellRows = dataRows.map { row in
            (0..<colCount).map { col in
                DocBlock.Cell(text: col < row.count ? row[col] : "")
            }
        }
        return (.table(rows: cellRows, widthsPercent: widths), i - startIndex)
    }

    private static func parsePipeCells(_ line: String) -> [String] {
        var stripped = line
        if stripped.hasPrefix("|") { stripped.removeFirst() }
        if stripped.hasSuffix("|") { stripped.removeLast() }
        return stripped.components(separatedBy: "|").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
    }

    private static func evenWidths(_ count: Int) -> [Int] {
        guard count > 0 else { return [] }
        let base = 100 / count
        var widths = Array(repeating: base, count: count)
        let remainder = 100 - base * count
        for i in 0..<remainder {
            widths[i] += 1
        }
        return widths
    }
}
