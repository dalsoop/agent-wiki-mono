import Foundation

extension Parser {
    // MARK: 블록 파싱

    /// `minIndent` 이상의 들여쓰기에서 시작하는 블록 노드 하나를 파싱한다.
    mutating func parseBlock(minIndent: Int) throws -> YAMLNode {
        skipBlanksAndComments()
        guard index < lines.count, lines[index].indent >= minIndent else { return .null }
        let line = lines[index]
        let content = line.content
        // 시퀀스?
        if isBlockSequenceEntry(content) {
            return try parseSequence(indent: line.indent)
        }
        // 매핑?
        if let _ = mappingColonIndex(content) {
            return try parseMapping(indent: line.indent)
        }
        // 단일 스칼라(플로우 포함) — 남은 첫 줄을 값으로 소비.
        index += 1
        return try parseInlineValue(content, parentIndent: line.indent)
    }

    mutating func parseSequence(indent: Int) throws -> YAMLNode {
        var items: [YAMLNode] = []
        while index < lines.count {
            skipBlanksAndComments()
            guard index < lines.count else { break }
            let line = lines[index]
            guard line.indent == indent, isBlockSequenceEntry(line.content) else { break }
            let afterDash = contentAfterDash(line.content)
            let dashOffset = line.indent // `-` 의 시작 열
            if afterDash.isEmpty {
                // 중첩 블록이 뒤따른다.
                index += 1
                let nested = try parseBlock(minIndent: dashOffset + 1)
                items.append(nested)
            } else if isBlockSequenceEntry(afterDash) || mappingColonIndex(afterDash) != nil {
                // `- - x`(중첩 시퀀스) 또는 `- key: val`(시퀀스 안 매핑이 같은 줄에서 시작).
                // 대시 뒤 첫 콘텐츠의 실제 열을 매핑 들여쓰기로 삼는다(형제 키 정렬).
                let keyColumn = dashOffset + contentColumnAfterDash(line.content)
                index += 1
                let node = try parseInlineEntry(afterDash, indent: keyColumn)
                items.append(node)
            } else {
                // `- value` 인라인 — 플로우/스칼라. 이 항목은 이 줄에서 끝.
                index += 1
                let value = try parseInlineValue(afterDash, parentIndent: dashOffset + 2)
                items.append(value)
            }
        }
        return .sequence(items)
    }

    mutating func parseMapping(indent: Int) throws -> YAMLNode {
        var pairs: [(key: YAMLNode, value: YAMLNode)] = []
        while index < lines.count {
            skipBlanksAndComments()
            guard index < lines.count else { break }
            let line = lines[index]
            guard line.indent == indent, let colon = mappingColonIndex(line.content) else { break }
            let (keyText, rawValue) = splitKeyValue(line.content, colon: colon)
            let key = parseScalarToken(keyText)
            index += 1
            let value: YAMLNode
            if let blockIndicator = blockScalarIndicator(rawValue) {
                // 블록 스칼라(| / >).
                value = try parseBlockScalar(indicator: blockIndicator, chomp: chompMarker(rawValue), parentIndent: indent)
            } else if rawValue.isEmpty {
                // 값이 같은 줄에 없음 — 다음 콘텐츠 줄로 결정.
                let peek = nextContentIndex()
                if let pi = peek, lines[pi].indent >= indent, isBlockSequenceEntry(lines[pi].content) {
                    // 블록 시퀀스 값은 키와 같은 들여쓰기를 허용한다(YAML 허용 형태).
                    let seqIndent = lines[pi].indent
                    index = pi
                    value = try parseSequence(indent: seqIndent)
                } else {
                    // 중첩 블록 매핑 — 더 깊은 들여쓰기.
                    let beforeNest = index
                    let nested = try parseBlock(minIndent: indent + 1)
                    if nested.isNull && index == beforeNest {
                        value = .null
                    } else {
                        value = nested
                    }
                }
            } else {
                value = try parseInlineValue(rawValue, parentIndent: indent + 2)
            }
            pairs.append((key: key, value: value))
        }
        return .mapping(pairs)
    }

    // MARK: 블록 스칼라

    mutating func parseBlockScalar(indicator: Character, chomp: Character?, parentIndent: Int) throws -> YAMLNode {
        // indicator 직후 줄부터, parentIndent 보다 깊은 들여쓰기 줄을 모은다.
        var collected: [String] = []
        let blockIndent: Int
        // 첫 콘텐츠 줄의 들여쓰기를 기준 블록 들여쓰기로 삼는다.
        if index < lines.count, !lines[index].isBlank, lines[index].indent > parentIndent {
            blockIndent = lines[index].indent
        } else if index < lines.count, lines[index].indent > parentIndent {
            blockIndent = lines[index].indent
        } else {
            blockIndent = parentIndent + 1
        }
        while index < lines.count {
            let line = lines[index]
            if line.isBlank {
                collected.append("")
                index += 1
                continue
            }
            if line.indent < blockIndent, !line.raw.trimmingCharacters(in: .whitespaces).isEmpty {
                break
            }
            let content = line.raw
            let prefix = String(repeating: " ", count: max(0, line.indent - blockIndent))
            collected.append(prefix + String(content.dropFirst(line.indent)))
            index += 1
        }
        let body: String
        if indicator == ">" {
            // folded — 빈 줄은 줄바꿈, 나머지는 공백으로 이어 붙인다(단순 근사).
            body = collected.joined(separator: " ")
        } else {
            body = collected.joined(separator: "\n")
        }
        let text: String
        switch chomp {
        case "-": text = body // strip
        case "+":
            text = body + "\n"
        default:
            text = body.isEmpty ? "" : body + "\n"
        }
        return .scalar(raw: text, plain: false)
    }
}
