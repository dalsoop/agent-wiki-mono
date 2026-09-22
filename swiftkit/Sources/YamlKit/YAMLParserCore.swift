import Foundation

/// 문서 단위 블록 파서. `YAMLParser.parseNode` 가 생성한다.
struct Parser {
    let lines: [YAMLLine]
    var index: Int

    init(text: String) {
        let rawLines = text.replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        var built: [YAMLLine] = []
        for raw in rawLines {
            built.append(YAMLLine(raw: raw))
        }
        lines = built
        index = 0
    }

    /// 문서 전체를 파싱. 문서 시작/끝 마커(`---`/`...`)는 건너뛴다.
    mutating func parseDocument() throws -> YAMLNode {
        skipMarkersAndBlanks()
        if index >= lines.count { return .null }
        let node = try parseBlock(minIndent: lines[index].indent)
        // 끝까지 소비하지 못해도 허용 — 잔여 줄은 무시한다(관대한 파싱).
        return node
    }

    mutating func skipBlanksAndComments() {
        while index < lines.count, lines[index].isBlank {
            index += 1
        }
    }

    /// 다음 비어있지 않은(콘텐츠 있는) 줄의 인덱스. 현재 인덱스는 옮기지 않는다(peek).
    func nextContentIndex() -> Int? {
        var i = index
        while i < lines.count, lines[i].isBlank { i += 1 }
        return i < lines.count ? i : nil
    }

    mutating func skipMarkersAndBlanks() {
        while index < lines.count {
            let line = lines[index]
            if line.isBlank { index += 1; continue }
            let trimmed = line.content.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" || trimmed == "..." { index += 1; continue }
            return
        }
    }
}
