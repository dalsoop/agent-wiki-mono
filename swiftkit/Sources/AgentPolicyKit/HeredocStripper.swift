import Foundation

struct HeredocStripper: Sendable {
    struct Target: Sendable {
        let delimiter: String
        let stripTabs: Bool
    }

    static func strip(_ script: String) -> String {
        let lines = script.components(separatedBy: "\n")
        var retained: [String] = []
        var pending: [Target] = []

        for line in lines {
            if let active = pending.first {
                if matchesEnd(line: line, target: active) {
                    pending.removeFirst()
                }
                continue
            }
            retained.append(line)
            pending.append(contentsOf: detectTargets(line))
        }

        return retained.joined(separator: "\n")
    }

    private static func matchesEnd(line: String, target: Target) -> Bool {
        var candidate = line
        if target.stripTabs {
            candidate = String(candidate.drop(while: { $0 == "\t" }))
        }
        let trimmed = candidate.trimmingCharacters(in: .whitespaces)
        return candidate == target.delimiter || trimmed == target.delimiter
    }

    private static func detectTargets(_ line: String) -> [Target] {
        guard line.contains("<<") else { return [] }
        return scanLineForDelimiters(line)
    }

    private static func scanLineForDelimiters(_ line: String) -> [Target] {
        let chars = Array(line)
        var targets: [Target] = []
        var i = 0
        var quote: Character?

        while i < chars.count {
            let c = chars[i]
            if let activeQuote = quote {
                if c == activeQuote { quote = nil }
                i += 1
                continue
            }
            if c == "'" || c == "\"" {
                quote = c
                i += 1
                continue
            }
            if isHeredocStart(chars, at: i) {
                let (target, nextIdx) = readTarget(chars, from: i + 2)
                if let target { targets.append(target) }
                i = nextIdx
                continue
            }
            i += 1
        }
        return targets
    }

    private static func isHeredocStart(_ chars: [Character], at idx: Int) -> Bool {
        guard idx + 1 < chars.count else { return false }
        guard chars[idx] == "<", chars[idx + 1] == "<" else { return false }
        guard idx + 2 < chars.count else { return true }
        return chars[idx + 2] != "<"
    }

    private static func readTarget(_ chars: [Character], from start: Int) -> (Target?, Int) {
        var i = start
        var stripTabs = false
        if i < chars.count, chars[i] == "-" {
            stripTabs = true
            i += 1
        }
        i = skipSpaces(chars, from: i)
        guard i < chars.count else { return (nil, i) }

        let first = chars[i]
        if first == "'" || first == "\"" {
            return readQuotedDelimiter(chars, from: i + 1, quote: first, stripTabs: stripTabs)
        }
        return readBareDelimiter(chars, from: i, stripTabs: stripTabs)
    }

    private static func skipSpaces(_ chars: [Character], from start: Int) -> Int {
        var i = start
        let spaceChars: Set<Character> = [" ", "\t"]
        while i < chars.count, spaceChars.contains(chars[i]) {
            i += 1
        }
        return i
    }

    private static func readQuotedDelimiter(_ chars: [Character], from start: Int, quote: Character, stripTabs: Bool) -> (Target?, Int) {
        var delim = ""
        var i = start
        while i < chars.count, chars[i] != quote {
            delim.append(chars[i])
            i += 1
        }
        let next = i < chars.count ? i + 1 : i
        guard !delim.isEmpty else { return (nil, next) }
        return (Target(delimiter: delim, stripTabs: stripTabs), next)
    }

    private static func readBareDelimiter(_ chars: [Character], from start: Int, stripTabs: Bool) -> (Target?, Int) {
        let terminators: Set<Character> = [" ", "\t", ";", "|", "&", ")", ">", "<", "("]
        var delim = ""
        var i = start
        while i < chars.count, !terminators.contains(chars[i]) {
            delim.append(chars[i])
            i += 1
        }
        guard !delim.isEmpty else { return (nil, i) }
        return (Target(delimiter: delim, stripTabs: stripTabs), i)
    }
}
