import Foundation

/// UTF-16 단위로 주석·문자열을 공백으로 가린다. `NSRange.location` 을 Character
/// offset 으로 쓰면 이모지 앞에서 삽입 위치가 밀리므로, 길이를 맞춘 뒤
/// `Range(_:in:)` 로만 되돌린다.
enum SourceCommentStringMasker {
    static func mask(_ source: String) -> String {
        var masker = Masker(source)
        masker.run()
        return masker.finished()
    }
}

private struct Masker {
    private enum State {
        case code
        case lineComment
        case blockComment
        case string
        case multiString
        case rawString(pounds: Int, multiline: Bool)
    }

    private let units: [UInt16]
    private var out: [UInt16]
    private var i = 0
    private var state = State.code
    private var escaped = false
    private var blockDepth = 0

    init(_ source: String) {
        let units = Array(source.utf16)
        self.units = units
        self.out = units
    }

    mutating func run() {
        while i < units.count {
            step()
        }
    }

    func finished() -> String {
        String(utf16CodeUnits: out, count: out.count)
    }

    private mutating func step() {
        switch state {
        case .code:
            stepCode()
        case .lineComment:
            stepLineComment()
        case .blockComment:
            stepBlockComment()
        case .string:
            stepString()
        case .multiString:
            stepMultiString()
        case .rawString(let pounds, let multiline):
            stepRawString(pounds: pounds, multiline: multiline)
        }
    }

    private mutating func stepCode() {
        guard !enterCommentOrLiteral() else { return }
        i += 1
    }

    private mutating func enterCommentOrLiteral() -> Bool {
        let b = units[i]
        let n1 = at(i + 1)
        switch (b, n1) {
        case (0x2F, 0x2F):
            blank(2)
            state = .lineComment
            return true
        case (0x2F, 0x2A):
            blank(2)
            blockDepth = 1
            state = .blockComment
            return true
        case (0x22, _):
            return enterQuotedLiteral()
        case (0x23, _):
            return enterRawLiteral()
        default:
            return false
        }
    }

    private mutating func enterQuotedLiteral() -> Bool {
        if at(i + 1) == 0x22, at(i + 2) == 0x22 {
            blank(3)
            state = .multiString
            return true
        }
        escaped = false
        blank(1)
        state = .string
        return true
    }

    private mutating func enterRawLiteral() -> Bool {
        let pounds = poundRun(at: i)
        let cursor = i + pounds
        guard cursor < units.count, units[cursor] == 0x22 else {
            return false
        }
        let multiline = at(cursor + 1) == 0x22 && at(cursor + 2) == 0x22
        blank(pounds + (multiline ? 3 : 1))
        state = .rawString(pounds: pounds, multiline: multiline)
        return true
    }

    private mutating func stepLineComment() {
        guard !isNewline(units[i]) else {
            i += 1
            state = .code
            return
        }
        blank(1)
    }

    private mutating func stepBlockComment() {
        switch (units[i], at(i + 1)) {
        case (0x2F, 0x2A):
            blank(2)
            blockDepth += 1
        case (0x2A, 0x2F):
            blank(2)
            blockDepth -= 1
            state = blockDepth == 0 ? .code : .blockComment
        default:
            blankKeepingNewline()
        }
    }

    private mutating func stepString() {
        switch (escaped, units[i]) {
        case (true, _):
            escaped = false
            blank(1)
        case (false, 0x5C):
            escaped = true
            blank(1)
        case (false, 0x22):
            blank(1)
            state = .code
        default:
            closeStringIfUnterminated()
        }
    }

    private mutating func closeStringIfUnterminated() {
        blankKeepingNewline()
        guard i > 0, isNewline(units[i - 1]) else { return }
        state = .code
    }

    private mutating func stepMultiString() {
        guard units[i] == 0x22, at(i + 1) == 0x22, at(i + 2) == 0x22 else {
            blankKeepingNewline()
            return
        }
        blank(3)
        state = .code
    }

    private mutating func stepRawString(pounds: Int, multiline: Bool) {
        guard let closer = rawCloserWidth(pounds: pounds, multiline: multiline) else {
            blankKeepingNewline()
            return
        }
        blank(closer)
        state = .code
    }

    private func rawCloserWidth(pounds: Int, multiline: Bool) -> Int? {
        if multiline, hasRawMultilineCloser(pounds: pounds) {
            return 3 + pounds
        }
        if !multiline, hasRawCloser(pounds: pounds) {
            return 1 + pounds
        }
        return nil
    }

    private func hasRawCloser(pounds: Int) -> Bool {
        guard units[i] == 0x22 else { return false }
        return poundRun(at: i + 1) >= pounds
    }

    private func hasRawMultilineCloser(pounds: Int) -> Bool {
        guard units[i] == 0x22, at(i + 1) == 0x22, at(i + 2) == 0x22 else {
            return false
        }
        return poundRun(at: i + 3) >= pounds
    }

    private func poundRun(at start: Int) -> Int {
        var n = 0
        var cursor = start
        while cursor < units.count, units[cursor] == 0x23 {
            n += 1
            cursor += 1
        }
        return n
    }

    private mutating func blankKeepingNewline() {
        if isNewline(units[i]) {
            out[i] = units[i]
        } else {
            out[i] = 0x20
        }
        i += 1
    }

    private mutating func blank(_ count: Int) {
        for _ in 0..<count {
            guard i < units.count else { return }
            blankKeepingNewline()
        }
    }

    private func at(_ n: Int) -> UInt16? {
        n < units.count ? units[n] : nil
    }

    private func isNewline(_ unit: UInt16) -> Bool {
        unit == 0x0A || unit == 0x0D
    }
}
