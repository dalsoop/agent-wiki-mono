import Foundation

struct ShellCommandSplitter: Sendable {
    static func split(_ script: String) -> [String] {
        let cleaned = HeredocStripper.strip(script)
        var commands: [String] = []
        var scanner = Scanner(chars: Array(cleaned))
        scanner.scan(into: &commands)
        return commands
    }
}

private struct Scanner {
    let chars: [Character]
    var index: Int = 0
    var current: String = ""

    mutating func scan(into commands: inout [String]) {
        while index < chars.count {
            let c = chars[index]
            if c == "\\" {
                consumeEscape()
                continue
            }
            if c == "'" {
                consumeSingleQuote()
                continue
            }
            if c == "\"" {
                consumeDoubleQuote(into: &commands)
                continue
            }
            if handleSubshell(into: &commands) {
                continue
            }
            if handleDelimiter(into: &commands) {
                continue
            }
            current.append(c)
            index += 1
        }
        flush(into: &commands)
    }

    private mutating func consumeEscape() {
        current.append(chars[index])
        index += 1
        if index < chars.count {
            current.append(chars[index])
            index += 1
        }
    }

    private mutating func consumeSingleQuote() {
        current.append(chars[index])
        index += 1
        while index < chars.count {
            let c = chars[index]
            current.append(c)
            index += 1
            if c == "'" { break }
        }
    }

    private mutating func consumeDoubleQuote(into commands: inout [String]) {
        current.append(chars[index])
        index += 1
        while index < chars.count {
            let c = chars[index]
            if c == "\\" {
                consumeEscape()
                continue
            }
            if c == "\"" {
                current.append(c)
                index += 1
                break
            }
            if handleSubshell(into: &commands) {
                continue
            }
            current.append(c)
            index += 1
        }
    }

    private mutating func handleSubshell(into commands: inout [String]) -> Bool {
        if isParenSubstitution() {
            index += 2
            let sub = extractMatchingParen()
            commands.append(contentsOf: ShellCommandSplitter.split(sub))
            return true
        }
        if chars[index] == "`" {
            index += 1
            let sub = extractMatchingBacktick()
            commands.append(contentsOf: ShellCommandSplitter.split(sub))
            return true
        }
        return false
    }

    private func isParenSubstitution() -> Bool {
        guard chars[index] == "$" else { return false }
        guard index + 1 < chars.count else { return false }
        return chars[index + 1] == "("
    }

    private mutating func extractMatchingParen() -> String {
        var depth = 1
        var sub = ""
        while index < chars.count {
            let c = chars[index]
            switch c {
            case "\\":
                sub.append(consumeParenEscape())
            case "'", "\"":
                sub.append(extractQuoted(quote: c))
            case "(":
                depth += 1
                sub.append(c)
                index += 1
            case ")":
                depth -= 1
                if depth == 0 {
                    index += 1
                    return sub
                }
                sub.append(c)
                index += 1
            default:
                sub.append(c)
                index += 1
            }
        }
        return sub
    }

    private mutating func consumeParenEscape() -> String {
        var res = "\\"
        index += 1
        if index < chars.count {
            res.append(chars[index])
            index += 1
        }
        return res
    }

    private mutating func extractQuoted(quote: Character) -> String {
        var res = String(quote)
        index += 1
        while index < chars.count {
            let c = chars[index]
            res.append(c)
            index += 1
            if c == quote { break }
        }
        return res
    }

    private mutating func extractMatchingBacktick() -> String {
        var sub = ""
        while index < chars.count {
            let c = chars[index]
            if c == "\\" {
                sub.append(c)
                index += 1
                if index < chars.count {
                    sub.append(chars[index])
                    index += 1
                }
                continue
            }
            if c == "`" {
                index += 1
                break
            }
            sub.append(c)
            index += 1
        }
        return sub
    }

    private mutating func handleDelimiter(into commands: inout [String]) -> Bool {
        let c = chars[index]
        if c == "\n" || c == ";" {
            flush(into: &commands)
            index += 1
            return true
        }
        if isDoubleOperator() {
            flush(into: &commands)
            index += 2
            return true
        }
        if c == "|" {
            flush(into: &commands)
            index += 1
            return true
        }
        if c == "&", !isRedirectionAmpersand() {
            flush(into: &commands)
            index += 1
            return true
        }
        if c == "(" || c == ")" {
            flush(into: &commands)
            index += 1
            return true
        }
        return false
    }

    private func isDoubleOperator() -> Bool {
        guard index + 1 < chars.count else { return false }
        let c1 = chars[index]
        let c2 = chars[index + 1]
        let isAnd = c1 == "&" && c2 == "&"
        let isOr = c1 == "|" && c2 == "|"
        return isAnd || isOr
    }

    private func isRedirectionAmpersand() -> Bool {
        if index > 0, chars[index - 1] == ">" { return true }
        if index + 1 < chars.count, chars[index + 1] == ">" { return true }
        return false
    }

    private mutating func flush(into commands: inout [String]) {
        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            commands.append(trimmed)
        }
        current = ""
    }
}
