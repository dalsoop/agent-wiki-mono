import Foundation

extension Parser {
    // MARK: 인라인 값/플로우

    /// 한 줄짜리 값(스칼라 또는 플로우 컬렉션)을 파싱. 매핑/시퀀스 같은 줄 시작도 처리.
    mutating func parseInlineValue(_ text: String, parentIndent: Int) throws -> YAMLNode {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        // 플로우 컬렉션이 여러 줄에 걸칠 수 있다 — 여는 괄호가 닫히지 않으면 이어 모은다.
        if let first = trimmed.first, first == "[" || first == "{" {
            return try parseFlow(gathered: trimmed, parentIndent: parentIndent)
        }
        return parseScalarToken(trimmed)
    }

    /// 시퀀스 항목이 같은 줄에서 매핑/시퀀스를 시작하는 경우의 재귀 파싱.
    mutating func parseInlineEntry(_ text: String, indent: Int) throws -> YAMLNode {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if let first = trimmed.first, first == "[" || first == "{" {
            return try parseFlow(gathered: trimmed, parentIndent: indent)
        }
        if isBlockSequenceEntry(trimmed) {
            // 같은 줄에 또 `-` 가 있는 중첩 시퀀스 — 가상 줄로 재구성해 파싱.
            var sub = Parser(text: String(repeating: " ", count: indent) + trimmed + "\n")
            return try sub.parseBlock(minIndent: indent)
        }
        if mappingColonIndex(trimmed) != nil {
            // `- key: val` 로 시작하는 매핑. 이후 들여쓰기 형제 키들도 같이 묶는다.
            // 형제 매핑 엔트리를 수집하기 위해 가상 라인 시퀀스를 주입해 파싱한다.
            return try collectContinuationMapping(firstLine: trimmed, indent: indent)
        }
        return parseScalarToken(trimmed)
    }

    /// 시퀀스 항목 직후 같은 줄에 시작된 매핑을, 이후 들여쓰기 된 키 줄들과 합쳐 파싱.
    mutating func collectContinuationMapping(firstLine: String, indent: Int) throws -> YAMLNode {
        var synthetic = [String(repeating: " ", count: indent) + firstLine]
        while index < lines.count {
            let line = lines[index]
            if line.isBlank { index += 1; continue }
            if line.indent >= indent {
                synthetic.append(line.raw)
                index += 1
            } else {
                break
            }
        }
        var sub = Parser(text: synthetic.joined(separator: "\n") + "\n")
        return try sub.parseBlock(minIndent: indent)
    }

    /// 플로우 컬렉션(`[]`/`{}`) — 여는/닫는 괄호가 짝맞을 때까지 줄을 모은 뒤 재귀 파싱.
    mutating func parseFlow(gathered initial: String, parentIndent: Int) throws -> YAMLNode {
        var buffer = initial
        var depthBrackets = flowDepth(initial)
        while depthBrackets > 0, index < lines.count {
            let line = lines[index]
            buffer += " " + line.content
            depthBrackets = flowDepth(buffer)
            index += 1
        }
        var scanner = FlowScanner(text: buffer)
        return try scanner.parseNode()
    }
}
