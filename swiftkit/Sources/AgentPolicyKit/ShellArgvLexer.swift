import Foundation

struct ShellArgvLexer: Sendable {
    static func parseArgv(_ command: String) -> [String] {
        let tokens = tokenize(command)
        guard !tokens.isEmpty else { return [] }
        let strippedVars = dropLeadingAssignments(tokens)
        guard !strippedVars.isEmpty else { return [] }
        return filterRedirections(strippedVars)
    }

    private static func dropLeadingAssignments(_ tokens: [String]) -> [String] {
        var start = 0
        while start < tokens.count {
            if isVariableAssignment(tokens[start]) {
                start += 1
            } else {
                break
            }
        }
        guard start < tokens.count else { return [] }
        return Array(tokens[start...])
    }

    private static func isVariableAssignment(_ token: String) -> Bool {
        guard let eqIdx = token.firstIndex(of: "="), eqIdx > token.startIndex else {
            return false
        }
        let name = token[..<eqIdx]
        guard let first = name.first, isIdentifierStart(first) else {
            return false
        }
        return name.allSatisfy(isIdentifierBody)
    }

    private static func isIdentifierStart(_ c: Character) -> Bool {
        c.isLetter || c == "_"
    }

    private static func isIdentifierBody(_ c: Character) -> Bool {
        if c == "_" { return true }
        return c.isLetter || c.isNumber
    }

    private static func filterRedirections(_ tokens: [String]) -> [String] {
        var filtered: [String] = []
        var skipNext = false
        let redirOps: Set<String> = [">", ">>", "<", "<<", ">&", "&>", "1>", "2>", "1>>", "2>>"]

        for arg in tokens {
            if skipNext {
                skipNext = false
                continue
            }
            if redirOps.contains(arg) {
                skipNext = true
                continue
            }
            if isSelfContainedRedirection(arg) {
                continue
            }
            filtered.append(arg)
        }
        return filtered
    }

    private static func isSelfContainedRedirection(_ arg: String) -> Bool {
        let knownDescriptors: Set<String> = ["2>&1", "1>&2", ">&1", ">&2"]
        if knownDescriptors.contains(arg) { return true }
        guard arg.count > 1 else { return false }
        let redirPrefixes: [String] = [">", "<", "1>", "2>"]
        return redirPrefixes.contains(where: { arg.hasPrefix($0) })
    }

    private static func tokenize(_ cmd: String) -> [String] {
        let chars = Array(cmd)
        var tokens: [String] = []
        var current = ""
        var inToken = false
        var i = 0

        while i < chars.count {
            let c = chars[i]
            if c == "\\" {
                let (ch, next) = consumeEscape(chars, at: i)
                appendChar(ch, to: &current, inToken: &inToken)
                i = next
                continue
            }
            if c == "'" || c == "\"" {
                let (quoted, next) = consumeQuoted(chars, at: i, quote: c)
                current.append(quoted)
                inToken = true
                i = next
                continue
            }
            if isWhitespace(c) {
                flushToken(&tokens, current: &current, inToken: &inToken)
                i += 1
                continue
            }
            current.append(c)
            inToken = true
            i += 1
        }
        flushToken(&tokens, current: &current, inToken: &inToken)
        return tokens
    }

    private static func appendChar(_ ch: Character?, to current: inout String, inToken: inout Bool) {
        guard let ch else { return }
        current.append(ch)
        inToken = true
    }

    private static let whitespaceChars: Set<Character> = [" ", "\t", "\n"]
    private static func isWhitespace(_ c: Character) -> Bool {
        whitespaceChars.contains(c)
    }

    private static func flushToken(_ tokens: inout [String], current: inout String, inToken: inout Bool) {
        guard inToken else { return }
        tokens.append(current)
        current = ""
        inToken = false
    }

    private static func consumeEscape(_ chars: [Character], at idx: Int) -> (Character?, Int) {
        guard idx + 1 < chars.count else { return (nil, idx + 1) }
        return (chars[idx + 1], idx + 2)
    }

    private static func consumeQuoted(_ chars: [Character], at idx: Int, quote: Character) -> (String, Int) {
        var str = ""
        var i = idx + 1
        while i < chars.count {
            let c = chars[i]
            if c == quote {
                return (str, i + 1)
            }
            str.append(c)
            i += 1
        }
        return (str, i)
    }
}
