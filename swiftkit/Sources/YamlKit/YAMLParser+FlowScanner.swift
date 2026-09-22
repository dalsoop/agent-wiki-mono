import Foundation

/// 플로우 컬렉션(`[]`/`{}`) 재귀 하강 스캐너.
struct FlowScanner {
    private let chars: [Character]
    private var pos: Int

    init(text: String) {
        chars = Array(text)
        pos = 0
    }

    mutating func parseNode() throws -> YAMLNode {
        skipSpace()
        guard pos < chars.count else { return .null }
        let ch = chars[pos]
        if ch == "[" { return try parseSeq() }
        if ch == "{" { return try parseMap() }
        if ch == "\"" || ch == "'" {
            let (raw, _) = readQuoted(quote: ch)
            return .scalar(raw: raw, plain: false)
        }
        return readPlainScalar()
    }

    private mutating func parseSeq() throws -> YAMLNode {
        pos += 1 // `[`
        var items: [YAMLNode] = []
        while true {
            skipSpace()
            if pos >= chars.count { break }
            if chars[pos] == "]" { pos += 1; break }
            if chars[pos] == "," { pos += 1; continue }
            items.append(try parseNode())
            skipSpace()
            if pos < chars.count, chars[pos] == "," { pos += 1 }
        }
        return .sequence(items)
    }

    private mutating func parseMap() throws -> YAMLNode {
        pos += 1 // `{`
        var pairs: [(key: YAMLNode, value: YAMLNode)] = []
        while true {
            skipSpace()
            if pos >= chars.count { break }
            if chars[pos] == "}" { pos += 1; break }
            if chars[pos] == "," { pos += 1; continue }
            let key = try parseFlowKey()
            skipSpace()
            var value: YAMLNode = .null
            if pos < chars.count, chars[pos] == ":" {
                pos += 1
                skipSpace()
                if pos < chars.count, chars[pos] != "," && chars[pos] != "}" {
                    value = try parseNode()
                }
            }
            pairs.append((key: key, value: value))
            skipSpace()
            if pos < chars.count, chars[pos] == "," { pos += 1 }
        }
        return .mapping(pairs)
    }

    private mutating func parseFlowKey() throws -> YAMLNode {
        skipSpace()
        guard pos < chars.count else { return .scalar(raw: "", plain: true) }
        let ch = chars[pos]
        if ch == "\"" || ch == "'" {
            let (raw, _) = readQuoted(quote: ch)
            return .scalar(raw: raw, plain: false)
        }
        var buf = ""
        while pos < chars.count {
            let c = chars[pos]
            if c == ":" || c == "," || c == "}" || c == "]" { break }
            buf.append(c)
            pos += 1
        }
        return .scalar(raw: buf.trimmingCharacters(in: .whitespaces), plain: true)
    }

    private mutating func readPlainScalar() -> YAMLNode {
        var buf = ""
        while pos < chars.count {
            let c = chars[pos]
            if c == "," || c == "]" || c == "}" { break }
            buf.append(c)
            pos += 1
        }
        return .scalar(raw: buf.trimmingCharacters(in: .whitespaces), plain: true)
    }

    private mutating func skipSpace() {
        while pos < chars.count, chars[pos].isWhitespace { pos += 1 }
    }
}

extension FlowScanner {
    private mutating func readQuoted(quote: Character) -> (String, Void) {
        pos += 1
        var buf = ""
        if quote == "'" {
            while pos < chars.count {
                let c = chars[pos]
                if c == "'" {
                    if pos + 1 < chars.count, chars[pos + 1] == "'" {
                        buf.append("'"); pos += 2; continue
                    }
                    pos += 1; break
                }
                buf.append(c); pos += 1
            }
        } else {
            while pos < chars.count {
                let c = chars[pos]
                if c == "\\", pos + 1 < chars.count {
                    let nxt = chars[pos + 1]
                    switch nxt {
                    case "n": buf.append("\n")
                    case "t": buf.append("\t")
                    case "r": buf.append("\r")
                    case "\\": buf.append("\\")
                    case "\"": buf.append("\"")
                    case "0": buf.append("\0")
                    default: buf.append(nxt)
                    }
                    pos += 2; continue
                }
                if c == "\"" { pos += 1; break }
                buf.append(c); pos += 1
            }
        }
        return (buf, ())
    }
}
