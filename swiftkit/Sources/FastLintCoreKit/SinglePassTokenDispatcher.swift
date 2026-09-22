import Foundation
import SwiftSourceKit

/// 토큰 종류 (초고속 정적 분석용 핵심 토큰 분류)
public enum SourceTokenKind: String, Sendable, CaseIterable {
    case identifier
    case keyword
    case stringLiteral
    case comment
    case importStatement
    case punctuation
    case line
}

/// 디스패치된 토큰 단위 정보
public struct DispatchedToken: Sendable, Equatable {
    public let kind: SourceTokenKind
    public let text: String
    public let line: Int
    public let column: Int
    public let utf8Offset: Int
    public let length: Int

    public init(
        kind: SourceTokenKind,
        text: String,
        line: Int,
        column: Int,
        utf8Offset: Int,
        length: Int
    ) {
        self.kind = kind
        self.text = text
        self.line = line
        self.column = column
        self.utf8Offset = utf8Offset
        self.length = length
    }
}

/// 단일 소스 패스에서 토큰 이벤트를 수신하는 프로토콜
public protocol SourceTokenSubscriber: Sendable {
    /// 구독자가 관심 있는 토큰 종류 (지정하지 않은 토큰은 디스패치 생략되어 0ms 오버헤드)
    var interestedKinds: Set<SourceTokenKind> { get }

    func onStart(source: SwiftSource)
    func onToken(_ token: DispatchedToken)
    func onLine(lineNumber: Int, lineText: String)
    func onEnd()
}

public extension SourceTokenSubscriber {
    func onStart(source: SwiftSource) {}
    func onToken(_ token: DispatchedToken) {}
    func onLine(lineNumber: Int, lineText: String) {}
    func onEnd() {}
}

/// Swift 소스 코드를 단 1회(O(N))만 바이트 단위로 순회하면서
/// 등록된 규칙 및 구독자들에게 토큰과 줄 이벤트를 멀티캐스트 디스패치하는 초고속 렉서 뼈대.
public final class SinglePassTokenDispatcher: Sendable {

    private let subscribers: [any SourceTokenSubscriber]

    public init(subscribers: [any SourceTokenSubscriber] = []) {
        self.subscribers = subscribers
    }

    /// SwiftSource 기반 단일 패스 디스패치 실행
    public func dispatch(source: SwiftSource) {
        for sub in subscribers {
            sub.onStart(source: source)
        }

        let bytes = Array(source.original.utf8)
        var ctx = DispatchContext(bytes: bytes)

        while ctx.offset < ctx.total {
            let b = bytes[ctx.offset]
            switch b {
            case 10, 13:
                handleNewline(ctx: &ctx)
            case 32, 9:
                ctx.column += 1
                ctx.offset += 1
            case 0x2F where isCommentStart(ctx: ctx):
                handleComment(ctx: &ctx)
            case 0x22:
                handleStringLiteral(ctx: &ctx)
            case _ where isIdentStart(b):
                handleIdentifier(ctx: &ctx)
            default:
                handlePunctuation(ctx: &ctx, byte: b)
            }
        }

        if ctx.lineStartOffset < ctx.total {
            dispatchLine(ctx: ctx, endOffset: ctx.total)
        }

        for sub in subscribers {
            sub.onEnd()
        }
    }

    /// 단순 텍스트 입력 디스패치 편의 함수
    public func dispatch(text: String) {
        dispatch(source: SwiftSource(text))
    }

    // MARK: - Private Helpers

    private struct DispatchContext {
        let bytes: [UInt8]
        let total: Int
        var offset: Int = 0
        var line: Int = 1
        var column: Int = 1
        var lineStartOffset: Int = 0

        init(bytes: [UInt8]) {
            self.bytes = bytes
            self.total = bytes.count
        }
    }

    private func dispatchToken(
        _ kind: SourceTokenKind,
        text: String,
        line: Int,
        col: Int,
        offset: Int,
        len: Int
    ) {
        let token = DispatchedToken(
            kind: kind,
            text: text,
            line: line,
            column: col,
            utf8Offset: offset,
            length: len
        )
        for sub in subscribers where sub.interestedKinds.contains(kind) {
            sub.onToken(token)
        }
    }

    private func dispatchLine(ctx: DispatchContext, endOffset: Int) {
        guard ctx.lineStartOffset <= endOffset, endOffset <= ctx.total else { return }
        let lineBytes = ctx.bytes[ctx.lineStartOffset..<endOffset]
        let lineStr = String(decoding: lineBytes, as: UTF8.self)
        for sub in subscribers where sub.interestedKinds.contains(.line) {
            sub.onLine(lineNumber: ctx.line, lineText: lineStr)
        }
    }

    private func handleNewline(ctx: inout DispatchContext) {
        let b = ctx.bytes[ctx.offset]
        dispatchLine(ctx: ctx, endOffset: ctx.offset)
        if b == 13 {
            ctx.offset += 1
            if ctx.offset < ctx.total && ctx.bytes[ctx.offset] == 10 {
                ctx.offset += 1
            }
        } else {
            ctx.offset += 1
        }
        ctx.line += 1
        ctx.column = 1
        ctx.lineStartOffset = ctx.offset
    }

    private func isCommentStart(ctx: DispatchContext) -> Bool {
        guard ctx.offset + 1 < ctx.total else { return false }
        let next = ctx.bytes[ctx.offset + 1]
        return next == 0x2F || next == 0x2A
    }

    private func handleComment(ctx: inout DispatchContext) {
        let start = ctx.offset
        let curLine = ctx.line
        let curCol = ctx.column
        let next = ctx.bytes[ctx.offset + 1]

        if next == 0x2F {
            consumeLineComment(ctx: &ctx)
        } else {
            consumeBlockComment(ctx: &ctx)
        }

        let len = ctx.offset - start
        let commentText = String(decoding: ctx.bytes[start..<ctx.offset], as: UTF8.self)
        dispatchToken(.comment, text: commentText, line: curLine, col: curCol, offset: start, len: len)
    }

    private func consumeLineComment(ctx: inout DispatchContext) {
        ctx.offset += 2
        ctx.column += 2
        while ctx.offset < ctx.total {
            let b = ctx.bytes[ctx.offset]
            if b == 10 || b == 13 { break }
            ctx.offset += 1
            ctx.column += 1
        }
    }

    private func consumeBlockComment(ctx: inout DispatchContext) {
        var depth = 1
        ctx.offset += 2
        ctx.column += 2
        while ctx.offset < ctx.total && depth > 0 {
            let b = ctx.bytes[ctx.offset]
            switch b {
            case 10:
                ctx.line += 1
                ctx.column = 1
                ctx.offset += 1
            case 0x2F where ctx.offset + 1 < ctx.total && ctx.bytes[ctx.offset + 1] == 0x2A:
                depth += 1
                ctx.offset += 2
                ctx.column += 2
            case 0x2A where ctx.offset + 1 < ctx.total && ctx.bytes[ctx.offset + 1] == 0x2F:
                depth -= 1
                ctx.offset += 2
                ctx.column += 2
            default:
                ctx.offset += 1
                ctx.column += 1
            }
        }
    }

    private func handleStringLiteral(ctx: inout DispatchContext) {
        let start = ctx.offset
        let curLine = ctx.line
        let curCol = ctx.column
        let isMultiline = hasMultilineQuote(ctx: ctx)

        if isMultiline {
            consumeMultilineString(ctx: &ctx)
        } else {
            consumeSingleLineString(ctx: &ctx)
        }

        let len = ctx.offset - start
        let str = String(decoding: ctx.bytes[start..<ctx.offset], as: UTF8.self)
        dispatchToken(.stringLiteral, text: str, line: curLine, col: curCol, offset: start, len: len)
    }

    private func hasMultilineQuote(ctx: DispatchContext) -> Bool {
        guard ctx.offset + 2 < ctx.total else { return false }
        return ctx.bytes[ctx.offset + 1] == 0x22 && ctx.bytes[ctx.offset + 2] == 0x22
    }

    private func consumeSingleLineString(ctx: inout DispatchContext) {
        ctx.offset += 1
        ctx.column += 1
        while ctx.offset < ctx.total {
            let b = ctx.bytes[ctx.offset]
            switch b {
            case 0x22:
                ctx.offset += 1
                ctx.column += 1
                return
            case 10, 13:
                return
            case 0x5C:
                ctx.offset += 2
                ctx.column += 2
            default:
                ctx.offset += 1
                ctx.column += 1
            }
        }
    }

    private func consumeMultilineString(ctx: inout DispatchContext) {
        ctx.offset += 3
        ctx.column += 3
        while ctx.offset + 2 < ctx.total {
            let b = ctx.bytes[ctx.offset]
            switch b {
            case 10:
                ctx.line += 1
                ctx.column = 1
                ctx.offset += 1
            case 0x5C:
                ctx.offset += 2
                ctx.column += 2
            case 0x22 where ctx.bytes[ctx.offset + 1] == 0x22 && ctx.bytes[ctx.offset + 2] == 0x22:
                ctx.offset += 3
                ctx.column += 3
                return
            default:
                ctx.offset += 1
                ctx.column += 1
            }
        }
    }

    private func handleIdentifier(ctx: inout DispatchContext) {
        let start = ctx.offset
        let curLine = ctx.line
        let curCol = ctx.column

        while ctx.offset < ctx.total && isIdentPart(ctx.bytes[ctx.offset]) {
            ctx.offset += 1
            ctx.column += 1
        }

        let word = String(decoding: ctx.bytes[start..<ctx.offset], as: UTF8.self)
        let len = ctx.offset - start

        if word == "import" {
            handleImportStatement(ctx: &ctx, start: start, line: curLine, col: curCol)
        } else if Self.SwiftKeywords.contains(word) {
            dispatchToken(.keyword, text: word, line: curLine, col: curCol, offset: start, len: len)
        } else {
            dispatchToken(.identifier, text: word, line: curLine, col: curCol, offset: start, len: len)
        }
    }

    private func handleImportStatement(
        ctx: inout DispatchContext,
        start: Int,
        line: Int,
        col: Int
    ) {
        while ctx.offset < ctx.total {
            let b = ctx.bytes[ctx.offset]
            switch b {
            case 10, 13, 0x3B:
                break
            default:
                ctx.offset += 1
                ctx.column += 1
                continue
            }
            break
        }
        let stmtBytes = ctx.bytes[start..<ctx.offset]
        let stmtText = String(decoding: stmtBytes, as: UTF8.self).trimmingCharacters(in: .whitespaces)
        dispatchToken(.importStatement, text: stmtText, line: line, col: col, offset: start, len: ctx.offset - start)
    }

    private func handlePunctuation(ctx: inout DispatchContext, byte: UInt8) {
        let curOffset = ctx.offset
        let curLine = ctx.line
        let curCol = ctx.column
        let charStr = String(decoding: [byte], as: UTF8.self)
        dispatchToken(.punctuation, text: charStr, line: curLine, col: curCol, offset: curOffset, len: 1)
        ctx.offset += 1
        ctx.column += 1
    }

    @inline(__always)
    private func isIdentStart(_ b: UInt8) -> Bool {
        if b == 0x5F { return true }
        let isLower = (b >= 0x61) && (b <= 0x7A)
        let isUpper = (b >= 0x41) && (b <= 0x5A)
        return isLower || isUpper
    }

    @inline(__always)
    private func isIdentPart(_ b: UInt8) -> Bool {
        let isDigit = (b >= 0x30) && (b <= 0x39)
        return isIdentStart(b) || isDigit
    }

    private static let SwiftKeywords: Set<String> = [
        "associatedtype", "class", "deinit", "enum", "extension", "fileprivate", "func", "import",
        "init", "inout", "internal", "let", "open", "operator", "private", "protocol", "public",
        "rethrows", "static", "struct", "subscript", "typealias", "var", "break", "case",
        "continue", "default", "defer", "do", "else", "fallthrough", "for", "guard", "if",
        "in", "repeat", "return", "switch", "where", "while", "as", "catch", "false",
        "is", "nil", "super", "self", "Self", "throw", "throws", "true", "try", "async", "await",
        "actor", "macro"
    ]
}
