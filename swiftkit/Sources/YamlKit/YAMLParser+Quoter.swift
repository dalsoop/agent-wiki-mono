import Foundation

/// 따옴표 스칼라 해제 보조.
enum Quoter {
    /// `quote` 로 시작하는 스칼라를 해제. 반환: (해제된 원문, 소비한 끝 인덱스의 뒤).
    static func unquote(_ text: String, quote: Character) -> (String, String.Index)? {
        let chars = Array(text)
        guard let first = chars.first, first == quote else { return nil }
        var buf = ""
        var i = 1
        if quote == "'" {
            while i < chars.count {
                let c = chars[i]
                if c == "'" {
                    if i + 1 < chars.count, chars[i + 1] == "'" {
                        buf.append("'"); i += 2; continue
                    }
                    i += 1
                    return (buf, String.Index(encodedOffset: i))
                }
                buf.append(c); i += 1
            }
            return (buf, text.endIndex)
        } else {
            while i < chars.count {
                let c = chars[i]
                if c == "\\" && i + 1 < chars.count {
                    let nxt = chars[i + 1]
                    switch nxt {
                    case "n": buf.append("\n")
                    case "t": buf.append("\t")
                    case "r": buf.append("\r")
                    case "\\": buf.append("\\")
                    case "\"": buf.append("\"")
                    case "0": buf.append("\0")
                    default: buf.append(nxt)
                    }
                    i += 2; continue
                }
                if c == "\"" {
                    i += 1
                    return (buf, String.Index(encodedOffset: i))
                }
                buf.append(c); i += 1
            }
            return (buf, text.endIndex)
        }
    }
}
