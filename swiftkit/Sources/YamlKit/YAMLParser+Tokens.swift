import Foundation

extension Parser {
    // MARK: 스칼라 토큰

    /// 따옴표/플레인 스칼라 하나를 파싱(키와 값에 공용).
    func parseScalarToken(_ text: String) -> YAMLNode {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return .null }
        if let ch = trimmed.first, ch == "\"" || ch == "'" {
            if let (unquoted, _) = Quoter.unquote(trimmed, quote: ch) {
                return .scalar(raw: unquoted, plain: false)
            }
        }
        return .scalar(raw: trimmed, plain: true)
    }

    // MARK: 보조

    func isBlockSequenceEntry(_ content: String) -> Bool {
        guard content.hasPrefix("-") else { return false }
        // `-` 단독이거나 `- ` 형태. `-value`(붙어있음)도 허용.
        if content == "-" { return true }
        let after = content.dropFirst()
        return after.first == " " || after.first == "\t" || after.isEmpty || content.dropFirst().first == "-"
    }

    /// 시퀀스 `- ` 뒤의 나머지 콘텐츠.
    func contentAfterDash(_ content: String) -> String {
        var rest = content.dropFirst()
        // 공백/탭 하나를 소비(dash 뒤 구분자).
        if let first = rest.first, first == " " || first == "\t" {
            rest = rest.dropFirst()
        }
        return String(rest).trimmingCharacters(in: .whitespaces)
    }

    /// `-` 뒤 첫 비공백 문자까지의 오프셋(열). `-` 자체 제외.
    /// `- x` → 2(공백 1 + x). `-x` → 1.
    func contentColumnAfterDash(_ content: String) -> Int {
        var offset = 1 // `-` 직후
        for ch in content.dropFirst() {
            if ch == " " || ch == "\t" { offset += 1 } else { break }
        }
        return offset
    }

    /// 매핑 구분 콜론의 위치(값 부분과 키 부분을 가르는 `: ` 또는 줄 끝 `:`).
    /// 따옴표 안의 콜론은 무시한다. 반환값은 콜론 문자의 인덱스.
    func mappingColonIndex(_ content: String) -> String.Index? {
        var inSingle = false
        var inDouble = false
        var escaped = false
        var flowDepth = 0
        var prev: Character = " "
        var idx = content.startIndex
        while idx < content.endIndex {
            let ch = content[idx]
            if escaped {
                escaped = false
            } else if inDouble {
                if ch == "\\" { escaped = true }
                else if ch == "\"" { inDouble = false }
            } else if inSingle {
                if ch == "'" { inSingle = false }
            } else {
                switch ch {
                case "\"": inDouble = true
                case "'": inSingle = true
                case "[", "{": flowDepth += 1
                case "]", "}": flowDepth -= 1
                case ":":
                    // 플로우 컬렉션 안의 콜론은 무시(`{a: 1}` 등).
                    guard flowDepth == 0 else { break }
                    let next = content.index(after: idx)
                    if next == content.endIndex || content[next] == " " || content[next] == "\t" {
                        return idx
                    }
                default:
                    break
                }
            }
            prev = ch
            idx = content.index(after: idx)
        }
        _ = prev
        return nil
    }

    func splitKeyValue(_ content: String, colon: String.Index) -> (String, String) {
        let key = String(content[..<colon]).trimmingCharacters(in: .whitespaces)
        let valueStart = content.index(after: colon)
        let value = String(content[valueStart...]).trimmingCharacters(in: .whitespaces)
        return (key, value)
    }

    func blockScalarIndicator(_ rawValue: String) -> Character? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first, first == "|" || first == ">" else { return nil }
        return first
    }

    func chompMarker(_ rawValue: String) -> Character? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first, first == "|" || first == ">" else { return nil }
        let rest = trimmed.dropFirst()
        if let ch = rest.first, ch == "-" || ch == "+" { return ch }
        return nil
    }

    func flowDepth(_ text: String) -> Int {
        var depth = 0
        var inSingle = false, inDouble = false, escaped = false
        for ch in text {
            if escaped { escaped = false; continue }
            if inDouble { if ch == "\\" { escaped = true }; if ch == "\"" { inDouble = false }; continue }
            if inSingle { if ch == "'" { inSingle = false }; continue }
            switch ch {
            case "\"": inDouble = true
            case "'": inSingle = true
            case "[", "{": depth += 1
            case "]", "}": depth -= 1
            default: break
            }
        }
        return depth
    }
}
