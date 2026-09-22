import Foundation

/// 파서가 소비하는 한 줄. 들여쓰기·주석 제거·원문을 같이 든다.
struct YAMLLine {
    let indent: Int
    let content: String   // 주석 제거·뒷공백 trim
    let raw: String       // 원문(블록 스칼라용)
    let isBlank: Bool     // 빈 줄 또는 주석 전용 줄

    init(raw: String) {
        self.raw = raw
        let (indent, body) = YAMLLine.leadingIndent(raw)
        self.indent = indent
        if body.isEmpty { content = ""; isBlank = true; return }
        if body.hasPrefix("#") { content = ""; isBlank = true; return }
        let stripped = YAMLLine.stripTrailingComment(body)
        if stripped.trimmingCharacters(in: .whitespaces).isEmpty {
            content = ""
            isBlank = true
        } else {
            content = stripped.trimmingCharacters(in: .whitespaces)
            isBlank = false
        }
    }

    static func leadingIndent(_ raw: String) -> (Int, String) {
        var count = 0
        for ch in raw {
            if ch == " " { count += 1 }
            else if ch == "\t" { count += 1 } // 탭을 공백1로(단순화)
            else { break }
        }
        return (count, String(raw.dropFirst(count)))
    }

    /// 줄 끝 주석(` #...`)을 제거 — 따옴표 안은 보존.
    static func stripTrailingComment(_ body: String) -> String {
        var inSingle = false, inDouble = false, escaped = false
        var prev: Character = " "
        var idx = body.startIndex
        while idx < body.endIndex {
            let ch = body[idx]
            if escaped { escaped = false }
            else if inDouble {
                if ch == "\\" { escaped = true }
                else if ch == "\"" { inDouble = false }
            } else if inSingle {
                if ch == "'" { inSingle = false }
            } else {
                switch ch {
                case "\"": inDouble = true
                case "'": inSingle = true
                case "#":
                    if prev == " " || prev == "\t" || idx == body.startIndex {
                        return String(body[..<idx])
                    }
                default: break
                }
            }
            prev = ch
            idx = body.index(after: idx)
        }
        return body
    }
}
