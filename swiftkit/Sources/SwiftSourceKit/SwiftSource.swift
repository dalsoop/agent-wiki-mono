import Foundation

/// Swift 소스에서 **코드만** 남긴 뷰. 주석과 문자열 리터럴을 같은 길이의 공백으로
/// 지워, 오프셋·줄 번호를 그대로 보존한다.
///
/// 왜 필요한가: grep 규칙의 오탐 둘이 전부 여기서 나왔다(2026-07-28 실측).
///
///  1. **주석 오탐** — 함정을 *설명하는* 주석에 금지 문자열이 나오는 게 정상인데
///     (그 주석이 재발 방지 문서다) 텍스트만 보면 위반으로 잡힌다. 실제로 규칙을
///     넣는 커밋이 자기 문서에 막혔다.
///  2. **줄 단위의 한계** — `^\s*//` 로 주석 줄을 빼는 방식은 **꼬리 주석**
///     (`let x = 1  // …rootURL`)을 못 걸러내고, 블록 주석과 문자열 리터럴도 못 본다.
///
/// 스캔은 UTF-8 바이트 인덱스(O(n)). `String.index(after:)` 를 파일 길이만큼
/// 돌리면 Linux CI 에서 SIGILL·수십 분이 난다(2026-08-15, !4795 358파일 27분 후 사망).
public struct SwiftSource: Sendable {
    /// 주석·문자열이 공백으로 치환된 소스. 길이와 줄 구조는 원본과 같다.
    /// 처음 읽을 때 한 번만 스캔한다 — 매니페스트·경로 전용 규칙은 이걸 안 본다.
    public var code: String {
        if cache.unparsed { return original }
        if let cached = cache.code { return cached }
        let value = Self.blankingCommentsAndStrings(original)
        cache.code = value
        return value
    }

    /// **주석만** 공백으로 치환된 소스 — 문자열 리터럴은 남는다.
    ///
    /// 값을 코드에 박는 위반(엔드포인트·경로·ID)은 **언제나 문자열 리터럴**이다.
    /// `code` 로 보면 그 위반이 통째로 사라진다 — 2026-08-11 실측: 하드코딩 규칙이
    /// `gitlab-ssh.internal.kr` 를 금지 목록에 갖고도 실제 위반 파일을 0건으로
    /// 답했다(문자열이라 지워져서). 주석 오탐만 피하면 되는 규칙은 이 뷰를 쓴다.
    /// 쓰는 규칙만 계산한다. 한 번 만들면 재사용.
    public var codeAndLiterals: String {
        if let cached = cache.literals { return cached }
        let value = Self.blankingComments(original)
        cache.literals = value
        return value
    }

    /// 원본 그대로 — 진단 메시지에 실제 줄을 보여줄 때 쓴다.
    public let original: String

    /// 주석 스캔을 이미 돌렸는가. 짧은 파일·바늘 없는 파일은 스캔 없이 끝나야 한다.
    public var isCommentScanned: Bool { cache.code != nil || cache.literals != nil }

    /// 원문 줄 수. 스캐너가 줄바꿈을 보존하므로 `code` 줄 수와 같다 — 길이 판정은 이걸 쓴다.
    public var lineCount: Int {
        var n = 1
        for b in original.utf8 where b == 10 { n += 1 }
        return n
    }

    private let cache: LiteralCache

    public init(_ text: String) {
        self.original = text
        self.cache = LiteralCache()
    }

    /// 주석 스트립 없이 원문만 싣는다. `Package.swift` 처럼 original.contains 만
    /// 보는 매니페스트 규칙용 — 358파일 배치에서 상태기계를 돌리지 않는다.
    public static func unparsed(_ text: String) -> SwiftSource {
        let cache = LiteralCache()
        cache.unparsed = true
        return SwiftSource(original: text, cache: cache)
    }

    private init(original: String, cache: LiteralCache) {
        self.original = original
        self.cache = cache
    }

    /// 주석만 지운다 — 문자열 리터럴은 그대로 둔다.
    public static func blankingComments(_ text: String) -> String {
        UTF8CommentScanner.blank(text, keepStrings: true)
    }

    /// 1-기반 줄 번호.
    public func line(atUTF16Offset offset: Int) -> Int {
        var line = 1, i = 0
        for ch in code.utf16 {
            if i >= offset { break }
            if ch == 10 { line += 1 }
            i += 1
        }
        return line
    }

    public func originalLine(_ number: Int) -> String {
        let lines = original.components(separatedBy: "\n")
        guard number >= 1, number <= lines.count else { return "" }
        return lines[number - 1]
    }

    /// 문자 단위 상태 기계. 줄 주석 · 블록 주석(중첩 포함) · 문자열 · 이스케이프를
    /// 구분해, 코드가 아닌 구간을 같은 길이의 공백(줄바꿈은 보존)으로 바꾼다.
    public static func blankingCommentsAndStrings(_ text: String) -> String {
        UTF8CommentScanner.blank(text, keepStrings: false)
    }
}

/// `codeAndLiterals` 지연 캐시. 규칙 대부분은 `code` 만 본다.
private final class LiteralCache: Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var _literals: String?
    nonisolated(unsafe) private var _code: String?
    nonisolated(unsafe) private var _unparsed = false

    var unparsed: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _unparsed
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _unparsed = newValue
        }
    }

    var code: String? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _code
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _code = newValue
        }
    }

    var literals: String? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _literals
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _literals = newValue
        }
    }
}

/// UTF-8 바이트 인덱스로 주석/문자열을 걷는다. `String.Index` 순회는 쓰지 않는다.
enum UTF8CommentScanner {
    fileprivate enum State { case code, lineComment, blockComment, string, rawString, multiString }

    static func blank(_ text: String, keepStrings: Bool) -> String {
        var scanner = Scanner(text: text, keepStrings: keepStrings)
        scanner.run()
        return scanner.finished(fallback: text)
    }
}

/// 상태 하나가 함수 하나. 옛 판은 `while` 안에 100줄짜리 `switch` 를 통째로 담아,
/// 문자열 처리 한 줄을 고치려면 다섯 상태를 다 읽어야 했다(제어흐름 4단 지적 7건이
/// 그 표면이었다). 상태 기계의 뜻은 그대로고 걸음만 이름을 얻었다.
private struct Scanner {
    typealias State = UTF8CommentScanner.State

    let u: [UInt8]
    let keepStrings: Bool
    var out: [UInt8]
    var i = 0
    var state = State.code
    var depth = 0
    var escaped = false

    init(text: String, keepStrings: Bool) {
        self.u = Array(text.utf8)
        self.keepStrings = keepStrings
        self.out = []
        self.out.reserveCapacity(u.count)
    }

    mutating func run() {
        while i < u.count {
            switch state {
            case .code: stepCode()
            case .lineComment: stepLineComment()
            case .blockComment: stepBlockComment()
            case .string: stepString()
            case .multiString: stepMultiString()
            case .rawString: stepRawString()
            }
        }
    }

    func finished(fallback: String) -> String {
        String(bytes: out, encoding: .utf8) ?? fallback
    }

    // MARK: - 상태별 한 걸음

    private mutating func stepCode() {
        guard !enterCommentOrLiteral() else { return }
        i += appendScalar(at: i)
    }

    private mutating func enterCommentOrLiteral() -> Bool {
        let b = u[i]
        let n1 = at(i + 1)
        switch (b, n1) {
        case (0x2F, 0x2F):
            enter(.lineComment, blanking: 2)
            return true
        case (0x2F, 0x2A):
            depth = 1
            enter(.blockComment, blanking: 2)
            return true
        case (0x23, 0x22):
            return enterPoundString()
        case (0x22, _):
            return enterQuoteString()
        default:
            return false
        }
    }

    private mutating func enterPoundString() -> Bool {
        if !keepStrings, at(i + 2) == 0x22, at(i + 3) == 0x22 {
            enter(.multiString, blanking: 4)
            return true
        }
        enter(.rawString, taking: 2)
        return true
    }

    private mutating func enterQuoteString() -> Bool {
        if at(i + 1) == 0x22, at(i + 2) == 0x22 {
            enter(.multiString, taking: 3)
            return true
        }
        escaped = false
        enter(.string, taking: 1)
        return true
    }

    private mutating func stepLineComment() {
        if isNL(u[i]) {
            state = .code
            out.append(10)
            i += 1
            return
        }
        i += blankScalar(at: i)
    }

    private mutating func stepBlockComment() {
        let b = u[i]
        let n1 = at(i + 1)
        switch (b, n1) {
        case (0x2F, 0x2A):
            depth += 1
            take(2, keep: false)
        case (0x2A, 0x2F):
            depth -= 1
            take(2, keep: false)
            if depth == 0 { state = .code }
        default:
            i += blankScalar(at: i)
        }
    }

    private mutating func stepString() {
        if keepStrings {
            stepStringKeeping()
            return
        }
        stepStringBlanking()
    }

    /// 문자열을 남기는 판 — 바이트는 그대로 싣고 종료만 판정한다.
    private mutating func stepStringKeeping() {
        let b = u[i]
        out.append(b)
        if escaped {
            escaped = false
        } else {
            switch b {
            case 0x5C: escaped = true
            case 0x22, 10: state = .code
            default: break
            }
        }
        i += 1
    }

    /// 문자열을 지우는 판 — 길이를 지키려 같은 폭의 공백으로 바꾼다.
    private mutating func stepStringBlanking() {
        let b = u[i]
        if escaped {
            escaped = false
            blankByte(b)
            i += 1
            return
        }
        switch b {
        case 0x5C:
            escaped = true
            blankByte(b)
            i += 1
        case 0x22:
            state = .code
            blankByte(b)
            i += 1
        case 10:
            state = .code
            out.append(10)
            i += 1
        default:
            i += blankScalar(at: i)
        }
    }

    private mutating func stepMultiString() {
        if u[i] == 0x22, at(i + 1) == 0x22, at(i + 2) == 0x22 {
            take(3, keep: keepStrings)
            state = .code
            return
        }
        stepScalarBody()
    }

    private mutating func stepRawString() {
        if u[i] == 0x22, at(i + 1) == 0x23 {
            take(2, keep: keepStrings)
            state = .code
            return
        }
        stepScalarBody()
    }

    /// 리터럴 본문 한 스칼라 — 남기는 판이면 싣고, 지우는 판이면 공백으로.
    private mutating func stepScalarBody() {
        if keepStrings {
            i += appendScalar(at: i)
            return
        }
        i += blankScalar(at: i)
    }

    // MARK: - 바이트 다루기

    /// 상태를 바꾸며 여는 표식 `count` 바이트를 공백으로 지운다.
    private mutating func enter(_ next: State, blanking count: Int) {
        state = next
        take(count, keep: false)
    }

    /// 상태를 바꾸며 여는 표식 `count` 바이트를 `keepStrings` 규율대로 처리한다.
    private mutating func enter(_ next: State, taking count: Int) {
        state = next
        take(count, keep: keepStrings)
    }

    private mutating func take(_ count: Int, keep: Bool) {
        for n in i..<(i + count) where n < u.count {
            if keep { out.append(u[n]) } else { blankByte(u[n]) }
        }
        i += count
    }

    private func at(_ n: Int) -> UInt8? { n < u.count ? u[n] : nil }

    private func isNL(_ b: UInt8) -> Bool { b == 10 }

    private mutating func blankByte(_ b: UInt8) { out.append(isNL(b) ? 10 : 32) }

    private func scalarWidth(at n: Int) -> Int {
        guard n < u.count else { return 0 }
        switch u[n] {
        case ..<0x80: return 1
        case ..<0xE0: return min(2, u.count - n)
        case ..<0xF0: return min(3, u.count - n)
        default: return min(4, u.count - n)
        }
    }

    private mutating func appendScalar(at n: Int) -> Int {
        let w = scalarWidth(at: n)
        out.append(contentsOf: u[n..<(n + w)])
        return w
    }

    /// 스칼라 1개 = 공백 1개. 오프셋(유니코드 스칼라 수)을 원문과 맞춘다.
    private mutating func blankScalar(at n: Int) -> Int {
        let w = scalarWidth(at: n)
        blankByte(u[n])
        return w
    }
}
