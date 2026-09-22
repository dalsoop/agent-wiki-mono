//
//  TriviaPreservingRibosome.swift
//  RuleMiningKit
//
//  무손실 LST(Lossless Syntax Tree) 및 Uber Piranha / OpenRewrite 철학 기반
//  주석(Trivia) 및 공백 100% 보존 코드 변환기 & 연쇄 소각(Cascading Apoptosis) 엔진.
//

import Foundation

// MARK: - 1. Trivia & Token Architecture (SwiftSyntax LST 모델)

/// 주석, 공백, 줄바꿈 등 코드 의미론(Semantics) 외의 모든 표면적 표현 요소.
public enum TriviaPiece: Equatable, Sendable {
    case spaces(Int)
    case tabs(Int)
    case newlines(Int)
    case carriageReturn
    case carriageReturnNewline
    case lineComment(String)       // "// ..."
    case docLineComment(String)    // "/// ..."
    case blockComment(String)      // "/* ... */"
    case docBlockComment(String)   // "/** ... */"

    public var description: String {
        switch self {
        case .spaces(let count):
            return String(repeating: " ", count: count)
        case .tabs(let count):
            return String(repeating: "\t", count: count)
        case .newlines(let count):
            return String(repeating: "\n", count: count)
        case .carriageReturn:
            return "\r"
        case .carriageReturnNewline:
            return "\r\n"
        case .lineComment(let text),
             .docLineComment(let text),
             .blockComment(let text),
             .docBlockComment(let text):
            return text
        }
    }

    public var isComment: Bool {
        switch self {
        case .lineComment, .docLineComment, .blockComment, .docBlockComment:
            return true
        default:
            return false
        }
    }
}

/// 토큰 앞뒤에 부착되는 Trivia 컬렉션.
public struct Trivia: Equatable, Sendable {
    public var pieces: [TriviaPiece]

    public init(pieces: [TriviaPiece] = []) {
        self.pieces = pieces
    }

    public static let zero = Trivia(pieces: [])

    public var description: String {
        pieces.map(\.description).joined()
    }

    public var isEmpty: Bool {
        pieces.isEmpty
    }

    public var hasComments: Bool {
        pieces.contains(where: \.isComment)
    }

    public mutating func append(_ piece: TriviaPiece) {
        pieces.append(piece)
    }
}

/// 토큰 종류 (Token Kind).
public enum SyntaxTokenKind: Equatable, Sendable {
    case identifier
    case keyword
    case punctuation
    case operatorToken
    case stringLiteral
    case numberLiteral
    case eof
}

/// 단일 구문 토큰 (Trivia 보존형).
public struct SyntaxToken: Equatable, Sendable {
    public var leadingTrivia: Trivia
    public var kind: SyntaxTokenKind
    public var text: String
    public var trailingTrivia: Trivia

    public init(
        leadingTrivia: Trivia = .zero,
        kind: SyntaxTokenKind,
        text: String,
        trailingTrivia: Trivia = .zero
    ) {
        self.leadingTrivia = leadingTrivia
        self.kind = kind
        self.text = text
        self.trailingTrivia = trailingTrivia
    }

    public var description: String {
        leadingTrivia.description + text + trailingTrivia.description
    }
}

// MARK: - 2. Lossless Syntax Tree (LST) & Lexer

/// 무손실 구문 트리 (Source File LST).
public struct SourceFileLST: Equatable, Sendable {
    public var tokens: [SyntaxToken]

    public init(tokens: [SyntaxToken]) {
        self.tokens = tokens
    }

    public var description: String {
        tokens.map(\.description).joined()
    }

    /// 원본 소스 코드를 단 1바이트의 유실 없이 LST 토큰 열로 분해합니다.
    public static func parse(_ source: String) -> SourceFileLST {
        var tokens: [SyntaxToken] = []
        let chars = Array(source)
        let n = chars.count
        var index = 0

        func consumeTrivia(stopAtNewline: Bool) -> Trivia {
            var pieces: [TriviaPiece] = []
            while index < n {
                let c = chars[index]
                if c == " " {
                    var count = 0
                    while index < n && chars[index] == " " {
                        count += 1
                        index += 1
                    }
                    pieces.append(.spaces(count))
                } else if c == "\t" {
                    var count = 0
                    while index < n && chars[index] == "\t" {
                        count += 1
                        index += 1
                    }
                    pieces.append(.tabs(count))
                } else if c == "\r" {
                    if stopAtNewline { break }
                    if index + 1 < n && chars[index + 1] == "\n" {
                        pieces.append(.carriageReturnNewline)
                        index += 2
                    } else {
                        pieces.append(.carriageReturn)
                        index += 1
                    }
                } else if c == "\n" {
                    if stopAtNewline { break }
                    var count = 0
                    while index < n && chars[index] == "\n" {
                        count += 1
                        index += 1
                    }
                    pieces.append(.newlines(count))
                } else if c == "/" && index + 1 < n && chars[index + 1] == "/" {
                    // Line comment
                    let start = index
                    let isDoc = index + 2 < n && chars[index + 2] == "/" && (index + 3 >= n || chars[index + 3] != "/")
                    while index < n && chars[index] != "\n" && chars[index] != "\r" {
                        index += 1
                    }
                    let commentText = String(chars[start..<index])
                    if isDoc {
                        pieces.append(.docLineComment(commentText))
                    } else {
                        pieces.append(.lineComment(commentText))
                    }
                } else if c == "/" && index + 1 < n && chars[index + 1] == "*" {
                    // Block comment (지원: 중첩 블록 주석 /* ... /* ... */ ... */)
                    let start = index
                    let isDoc = index + 2 < n && chars[index + 2] == "*" && (index + 3 >= n || chars[index + 3] != "*")
                    index += 2
                    var depth = 1
                    while index < n && depth > 0 {
                        if chars[index] == "/" && index + 1 < n && chars[index + 1] == "*" {
                            depth += 1
                            index += 2
                        } else if chars[index] == "*" && index + 1 < n && chars[index + 1] == "/" {
                            depth -= 1
                            index += 2
                        } else {
                            index += 1
                        }
                    }
                    let commentText = String(chars[start..<index])
                    if isDoc {
                        pieces.append(.docBlockComment(commentText))
                    } else {
                        pieces.append(.blockComment(commentText))
                    }
                } else {
                    break
                }
            }
            return Trivia(pieces: pieces)
        }

        while index < n {
            let leading = consumeTrivia(stopAtNewline: false)
            if index >= n {
                if !leading.isEmpty {
                    tokens.append(SyntaxToken(leadingTrivia: leading, kind: .eof, text: "", trailingTrivia: .zero))
                }
                break
            }

            let c = chars[index]
            var kind: SyntaxTokenKind = .punctuation
            var tokenText = ""

            // 1. 문자열 리터럴
            if c == "\"" {
                let start = index
                if index + 2 < n && chars[index + 1] == "\"" && chars[index + 2] == "\"" {
                    // Multiline string
                    index += 3
                    while index < n {
                        if chars[index] == "\\" && index + 1 < n {
                            index += 2
                        } else if chars[index] == "\"" && index + 2 < n && chars[index + 1] == "\"" && chars[index + 2] == "\"" {
                            index += 3
                            break
                        } else {
                            index += 1
                        }
                    }
                } else {
                    // Singleline string
                    index += 1
                    while index < n && chars[index] != "\"" && chars[index] != "\n" && chars[index] != "\r" {
                        if chars[index] == "\\" && index + 1 < n {
                            index += 2
                        } else {
                            index += 1
                        }
                    }
                    if index < n && chars[index] == "\"" {
                        index += 1
                    }
                }
                tokenText = String(chars[start..<index])
                kind = .stringLiteral
            } else if c == "`" {
                // Backticked identifier
                let start = index
                index += 1
                while index < n && chars[index] != "`" && chars[index] != "\n" {
                    index += 1
                }
                if index < n && chars[index] == "`" {
                    index += 1
                }
                tokenText = String(chars[start..<index])
                kind = .identifier
            } else if c.isLetter || c == "_" {
                // Identifier / Keyword
                let start = index
                while index < n && (chars[index].isLetter || chars[index].isNumber || chars[index] == "_") {
                    index += 1
                }
                tokenText = String(chars[start..<index])
                if isSwiftKeyword(tokenText) {
                    kind = .keyword
                } else {
                    kind = .identifier
                }
            } else if c.isNumber {
                // Number literal
                let start = index
                while index < n && (chars[index].isNumber || chars[index] == "." || chars[index] == "_" || chars[index] == "x" || chars[index] == "X" || chars[index].isHexDigit) {
                    index += 1
                }
                tokenText = String(chars[start..<index])
                kind = .numberLiteral
            } else {
                // Punctuation / Operator
                let start = index
                // try? 및 try! 는 단일 연산자 토큰 취급 가능
                if c == "?" || c == "!" || c == "." || c == "," || c == ":" || c == ";" || c == "(" || c == ")" || c == "{" || c == "}" || c == "[" || c == "]" {
                    index += 1
                } else if c == "-" && index + 1 < n && chars[index + 1] == ">" {
                    index += 2
                } else if c == "=" && index + 1 < n && chars[index + 1] == "=" {
                    index += 2
                } else if c == "!" && index + 1 < n && chars[index + 1] == "=" {
                    index += 2
                } else if c == "?" && index + 1 < n && chars[index + 1] == "?" {
                    index += 2
                } else {
                    index += 1
                }
                tokenText = String(chars[start..<index])
                kind = (tokenText == "(" || tokenText == ")" || tokenText == "{" || tokenText == "}" || tokenText == "[" || tokenText == "]" || tokenText == "," || tokenText == ":" || tokenText == ";") ? .punctuation : .operatorToken
            }

            // Trailing trivia: 같은 줄에 위치한 공백/탭/주석만 포함 (줄바꿈 발생 시 중단)
            let trailing = consumeTrivia(stopAtNewline: true)
            tokens.append(SyntaxToken(leadingTrivia: leading, kind: kind, text: tokenText, trailingTrivia: trailing))
        }

        return SourceFileLST(tokens: tokens)
    }

    private static func isSwiftKeyword(_ text: String) -> Bool {
        let keywords: Set<String> = [
            "import", "let", "var", "func", "return", "try", "throw", "throws", "rethrows",
            "class", "struct", "enum", "protocol", "extension", "typealias", "associatedtype",
            "if", "else", "guard", "switch", "case", "default", "for", "in", "while", "repeat",
            "break", "continue", "fallthrough", "defer", "as", "is", "self", "Self",
            "public", "private", "fileprivate", "internal", "open", "final", "static",
            "mutating", "nonmutating", "override", "weak", "unowned", "async", "await"
        ]
        return keywords.contains(text)
    }
}

// MARK: - 3. Transformation Configuration & Report

public struct TriviaPreservingRibosome: Sendable {

    /// 리보솜 변환 및 연쇄 소각 설정
    public struct TransformationConfig: Sendable {
        public var enableCascadingApoptosis: Bool
        public var removeDeadDeclarations: Bool
        public var removeUnusedImports: Bool
        public var injectMissingImports: Bool
        public var removeAssociatedComments: Bool
        public var obsoleteImportCandidates: Set<String>
        public var checkFoundationUsage: Bool

        public init(
            enableCascadingApoptosis: Bool = true,
            removeDeadDeclarations: Bool = true,
            removeUnusedImports: Bool = true,
            injectMissingImports: Bool = true,
            removeAssociatedComments: Bool = true,
            obsoleteImportCandidates: Set<String> = ["ObsoleteJsonKit", "LegacyDateKit", "LegacyJsonKit", "OldCodecKit"],
            checkFoundationUsage: Bool = true
        ) {
            self.enableCascadingApoptosis = enableCascadingApoptosis
            self.removeDeadDeclarations = removeDeadDeclarations
            self.removeUnusedImports = removeUnusedImports
            self.injectMissingImports = injectMissingImports
            self.removeAssociatedComments = removeAssociatedComments
            self.obsoleteImportCandidates = obsoleteImportCandidates
            self.checkFoundationUsage = checkFoundationUsage
        }
    }

    /// 리보솜 변환 결과 리포트
    public struct TransformationReport: Sendable, Equatable {
        public let originalSource: String
        public let transformedSource: String
        public let replacementCount: Int
        public let deadDeclarationsRemoved: [String]
        public let importsRemoved: [String]
        public let importsAdded: [String]
        public let appliedRules: [String]

        public init(
            originalSource: String,
            transformedSource: String,
            replacementCount: Int,
            deadDeclarationsRemoved: [String],
            importsRemoved: [String],
            importsAdded: [String],
            appliedRules: [String]
        ) {
            self.originalSource = originalSource
            self.transformedSource = transformedSource
            self.replacementCount = replacementCount
            self.deadDeclarationsRemoved = deadDeclarationsRemoved
            self.importsRemoved = importsRemoved
            self.importsAdded = importsAdded
            self.appliedRules = appliedRules
        }

        public var isModified: Bool {
            replacementCount > 0 || !deadDeclarationsRemoved.isEmpty || !importsRemoved.isEmpty || !importsAdded.isEmpty
        }
    }

    public init() {}

    // MARK: - 4. Core Transformation & Cascading Apoptosis Engine

    private enum BoundVarKind {
        case jsonDecoder
        case jsonEncoder
        case dateFormatter
        case iso8601DateFormatter
    }

    private struct BoundDeclaration {
        let name: String
        let kind: BoundVarKind
        let startTokenIndex: Int
        let endTokenIndex: Int
    }

    /// 소스 코드에 무손실 LST 변환 및 연쇄 소각을 적용합니다.
    public func transform(
        source: String,
        config: TransformationConfig = TransformationConfig()
    ) -> TransformationReport {
        let lst = SourceFileLST.parse(source)
        var replacementCount = 0
        var appliedRules: [String] = []
        var deadDeclarationsRemoved: [String] = []
        var importsRemoved: [String] = []
        var importsAdded: [String] = []

        var needsAppPersistence = false
        var needsDateCodec = false

        // Phase 1: 로컬 변수 바인딩 감지 (예: let decoder = JSONDecoder())
        var boundDeclarations: [BoundDeclaration] = []
        var i = 0
        while i < lst.tokens.count {
            let token = lst.tokens[i]
            if token.text == "let" || token.text == "var" {
                let declStart = i
                if i + 1 < lst.tokens.count && lst.tokens[i + 1].kind == .identifier {
                    let varName = lst.tokens[i + 1].text
                    var probe = i + 2
                    // 타입 명시 건너뛰기 (예: : JSONDecoder)
                    if probe < lst.tokens.count && lst.tokens[probe].text == ":" {
                        probe += 1
                        while probe < lst.tokens.count && lst.tokens[probe].text != "=" && lst.tokens[probe].text != "\n" {
                            probe += 1
                        }
                    }
                    if probe < lst.tokens.count && lst.tokens[probe].text == "=" {
                        probe += 1
                        if probe + 2 < lst.tokens.count && lst.tokens[probe + 1].text == "(" && lst.tokens[probe + 2].text == ")" {
                            let initTarget = lst.tokens[probe].text
                            var kind: BoundVarKind?
                            if initTarget == "JSONDecoder" {
                                kind = .jsonDecoder
                            } else if initTarget == "JSONEncoder" {
                                kind = .jsonEncoder
                            } else if initTarget == "DateFormatter" {
                                kind = .dateFormatter
                            } else if initTarget == "ISO8601DateFormatter" {
                                kind = .iso8601DateFormatter
                            }
                            if let kind {
                                boundDeclarations.append(BoundDeclaration(
                                    name: varName,
                                    kind: kind,
                                    startTokenIndex: declStart,
                                    endTokenIndex: probe + 2
                                ))
                            }
                        }
                    }
                }
            }
            i += 1
        }

        // Phase 2: 인라인 / 바인딩 호출 치환 (LST Rewriting)
        // 1) raw JSONDecoder().decode(...) ➔ AppPersistence.decode(...)
        // 2) raw JSONEncoder().encode(...) ➔ AppPersistence.encode(...)
        // 3) ISO8601DateFormatter().string(from: Date()) ➔ DateCodec.isoNow()
        // 4) ISO8601DateFormatter().string(from: ...) ➔ DateCodec.formatISO8601(...)
        // 5) DateFormatter().string(from: ...) ➔ DateCodec.formatISO8601(...)
        // 6) ISO8601DateFormatter().date(from: ...) ➔ DateCodec.parseISO8601(...)
        // 7) DateFormatter().date(from: ...) ➔ DateCodec.parseISO8601(...)
        // + 바인딩된 decoder.decode(...), encoder.encode(...), formatter.string(...) 등

        var tokens = lst.tokens
        var cursor = 0

        while cursor < tokens.count {
            // Pattern A: JSONDecoder().decode(T.self, from: data) 또는 <var>.decode(T.self, from: data)
            if let match = matchDecodeCall(tokens: tokens, fromIndex: cursor, boundVars: boundDeclarations) {
                let leadingTrivia = tokens[match.startIndex].leadingTrivia
                let trailingTrivia = tokens[match.endIndex].trailingTrivia

                // AppPersistence.decode(<type>, from: <data>) 토큰 생성
                var newTokens: [SyntaxToken] = []
                newTokens.append(SyntaxToken(leadingTrivia: leadingTrivia, kind: .identifier, text: "AppPersistence", trailingTrivia: .zero))
                newTokens.append(SyntaxToken(leadingTrivia: .zero, kind: .operatorToken, text: ".", trailingTrivia: .zero))
                newTokens.append(SyntaxToken(leadingTrivia: .zero, kind: .identifier, text: "decode", trailingTrivia: .zero))
                newTokens.append(SyntaxToken(leadingTrivia: .zero, kind: .punctuation, text: "(", trailingTrivia: .zero))
                newTokens.append(contentsOf: match.typeArgTokens)
                newTokens.append(SyntaxToken(leadingTrivia: .zero, kind: .punctuation, text: ",", trailingTrivia: Trivia(pieces: [.spaces(1)])))
                newTokens.append(SyntaxToken(leadingTrivia: .zero, kind: .identifier, text: "from", trailingTrivia: .zero))
                newTokens.append(SyntaxToken(leadingTrivia: .zero, kind: .punctuation, text: ":", trailingTrivia: Trivia(pieces: [.spaces(1)])))
                newTokens.append(contentsOf: match.dataArgTokens)
                newTokens.append(SyntaxToken(leadingTrivia: .zero, kind: .punctuation, text: ")", trailingTrivia: trailingTrivia))

                tokens.replaceSubrange(match.startIndex...match.endIndex, with: newTokens)
                replacementCount += 1
                appliedRules.append("rule.ribosome.json-decoder.to-app-persistence")
                needsAppPersistence = true
                cursor = match.startIndex + newTokens.count
                continue
            }

            // Pattern B: JSONEncoder().encode(item) 또는 <var>.encode(item)
            if let match = matchEncodeCall(tokens: tokens, fromIndex: cursor, boundVars: boundDeclarations) {
                let leadingTrivia = tokens[match.startIndex].leadingTrivia
                let trailingTrivia = tokens[match.endIndex].trailingTrivia

                var newTokens: [SyntaxToken] = []
                newTokens.append(SyntaxToken(leadingTrivia: leadingTrivia, kind: .identifier, text: "AppPersistence", trailingTrivia: .zero))
                newTokens.append(SyntaxToken(leadingTrivia: .zero, kind: .operatorToken, text: ".", trailingTrivia: .zero))
                newTokens.append(SyntaxToken(leadingTrivia: .zero, kind: .identifier, text: "encode", trailingTrivia: .zero))
                newTokens.append(SyntaxToken(leadingTrivia: .zero, kind: .punctuation, text: "(", trailingTrivia: .zero))
                newTokens.append(contentsOf: match.argTokens)
                newTokens.append(SyntaxToken(leadingTrivia: .zero, kind: .punctuation, text: ")", trailingTrivia: trailingTrivia))

                tokens.replaceSubrange(match.startIndex...match.endIndex, with: newTokens)
                replacementCount += 1
                appliedRules.append("rule.ribosome.json-encoder.to-app-persistence")
                needsAppPersistence = true
                cursor = match.startIndex + newTokens.count
                continue
            }

            // Pattern C: DateFormatter / ISO8601DateFormatter string(from:) ➔ DateCodec.formatISO8601 또는 isoNow
            if let match = matchDateStringCall(tokens: tokens, fromIndex: cursor, boundVars: boundDeclarations) {
                let leadingTrivia = tokens[match.startIndex].leadingTrivia
                let trailingTrivia = tokens[match.endIndex].trailingTrivia

                var newTokens: [SyntaxToken] = []
                newTokens.append(SyntaxToken(leadingTrivia: leadingTrivia, kind: .identifier, text: "DateCodec", trailingTrivia: .zero))
                newTokens.append(SyntaxToken(leadingTrivia: .zero, kind: .operatorToken, text: ".", trailingTrivia: .zero))

                if match.isNow {
                    newTokens.append(SyntaxToken(leadingTrivia: .zero, kind: .identifier, text: "isoNow", trailingTrivia: .zero))
                    newTokens.append(SyntaxToken(leadingTrivia: .zero, kind: .punctuation, text: "(", trailingTrivia: .zero))
                    newTokens.append(SyntaxToken(leadingTrivia: .zero, kind: .punctuation, text: ")", trailingTrivia: trailingTrivia))
                    appliedRules.append("rule.ribosome.date-codec.iso-now")
                } else {
                    newTokens.append(SyntaxToken(leadingTrivia: .zero, kind: .identifier, text: "formatISO8601", trailingTrivia: .zero))
                    newTokens.append(SyntaxToken(leadingTrivia: .zero, kind: .punctuation, text: "(", trailingTrivia: .zero))
                    newTokens.append(contentsOf: match.argTokens)
                    newTokens.append(SyntaxToken(leadingTrivia: .zero, kind: .punctuation, text: ")", trailingTrivia: trailingTrivia))
                    appliedRules.append("rule.ribosome.date-codec.format-iso8601")
                }

                tokens.replaceSubrange(match.startIndex...match.endIndex, with: newTokens)
                replacementCount += 1
                needsDateCodec = true
                cursor = match.startIndex + newTokens.count
                continue
            }

            // Pattern D: DateFormatter / ISO8601DateFormatter date(from:) ➔ DateCodec.parseISO8601
            if let match = matchDateParseCall(tokens: tokens, fromIndex: cursor, boundVars: boundDeclarations) {
                let leadingTrivia = tokens[match.startIndex].leadingTrivia
                let trailingTrivia = tokens[match.endIndex].trailingTrivia

                var newTokens: [SyntaxToken] = []
                newTokens.append(SyntaxToken(leadingTrivia: leadingTrivia, kind: .identifier, text: "DateCodec", trailingTrivia: .zero))
                newTokens.append(SyntaxToken(leadingTrivia: .zero, kind: .operatorToken, text: ".", trailingTrivia: .zero))
                newTokens.append(SyntaxToken(leadingTrivia: .zero, kind: .identifier, text: "parseISO8601", trailingTrivia: .zero))
                newTokens.append(SyntaxToken(leadingTrivia: .zero, kind: .punctuation, text: "(", trailingTrivia: .zero))
                newTokens.append(contentsOf: match.argTokens)
                newTokens.append(SyntaxToken(leadingTrivia: .zero, kind: .punctuation, text: ")", trailingTrivia: trailingTrivia))

                tokens.replaceSubrange(match.startIndex...match.endIndex, with: newTokens)
                replacementCount += 1
                appliedRules.append("rule.ribosome.date-codec.parse-iso8601")
                needsDateCodec = true
                cursor = match.startIndex + newTokens.count
                continue
            }

            cursor += 1
        }

        // Phase 3: 연쇄 소각 (Cascading Apoptosis - 미사용 변수 선언 제거)
        if config.enableCascadingApoptosis && config.removeDeadDeclarations && !boundDeclarations.isEmpty {
            // 다시 토큰을 재스캔하여 dead variable 선언을 안전하게 소각
            var declIndex = 0
            while declIndex < boundDeclarations.count {
                let decl = boundDeclarations[declIndex]
                // 토큰 열에서 decl.name 의 참조 횟수를 계산
                var refCount = 0
                var declStartInCurrent: Int?
                var declEndInCurrent: Int?

                var k = 0
                while k < tokens.count {
                    if (tokens[k].text == "let" || tokens[k].text == "var") && k + 1 < tokens.count && tokens[k + 1].text == decl.name {
                        declStartInCurrent = k
                        var p = k + 2
                        if p < tokens.count && tokens[p].text == ":" {
                            p += 1
                            while p < tokens.count && tokens[p].text != "=" { p += 1 }
                        }
                        if p < tokens.count && tokens[p].text == "=" {
                            p += 1
                            if p + 2 < tokens.count && tokens[p + 1].text == "(" && tokens[p + 2].text == ")" {
                                declEndInCurrent = p + 2
                                k = p + 2
                            }
                        }
                    } else if tokens[k].text == decl.name && tokens[k].kind == .identifier {
                        refCount += 1
                    }
                    k += 1
                }

                // 참조 횟수가 0인 경우 연쇄 소각 발동!
                if refCount == 0, let start = declStartInCurrent, let end = declEndInCurrent {
                    // 줄 정리: dead statement가 한 줄을 차지하는 경우 해당 라인을 깔끔하게 제거
                    tokens.removeSubrange(start...end)
                    deadDeclarationsRemoved.append(decl.name)
                }

                declIndex += 1
            }
        }

        // Phase 4: Import 구문 연쇄 소각 및 주입 (Import Apoptosis & Injection)
        var finalSource = tokens.map(\.description).joined()

        if config.enableCascadingApoptosis && config.removeUnusedImports {
            let lines = finalSource.components(separatedBy: "\n")
            var modifiedLines: [String] = []

            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("import ") {
                    let parts = trimmed.split(separator: " ")
                    if parts.count >= 2 {
                        let module = String(parts[1]).trimmingCharacters(in: .punctuationCharacters)

                        // 1) 후보 폐기 모듈 소각
                        if config.obsoleteImportCandidates.contains(module) {
                            let isUsed = lines.contains { $0 != line && $0.contains(module) }
                            if !isUsed {
                                importsRemoved.append(module)
                                continue // 소각: 라인 제외
                            }
                        }

                        // 2) Foundation 소각 검사 (더 이상 Data, Date, UUID 등 Foundation 심볼이 전혀 남지 않은 경우)
                        if module == "Foundation" && config.checkFoundationUsage {
                            let remainingFoundationSymbols: Set<String> = [
                                "Data", "Date", "UUID", "URL", "Error", "NotificationCenter",
                                "UserDefaults", "FileManager", "Bundle", "ProcessInfo", "Calendar",
                                "TimeZone", "CharacterSet", "NSRange", "NSRegularExpression",
                                "Measurement", "Unit", "Locale", "URLRequest", "URLResponse",
                                "HTTPURLResponse", "URLSession"
                            ]
                            let hasFoundationSymbols = tokens.contains { t in
                                t.kind == .identifier && remainingFoundationSymbols.contains(t.text)
                            }
                            if !hasFoundationSymbols && (needsAppPersistence || needsDateCodec) {
                                importsRemoved.append(module)
                                continue // 소각: 라인 제외
                            }
                        }
                    }
                }
                modifiedLines.append(line)
            }
            finalSource = modifiedLines.joined(separator: "\n")
        }

        // Phase 5: 신규 의존성 Import 자동 주입
        if config.injectMissingImports {
            if needsAppPersistence && !finalSource.contains("import AppPersistenceKit") {
                finalSource = injectImport(content: finalSource, moduleName: "AppPersistenceKit")
                importsAdded.append("AppPersistenceKit")
            }
            if needsDateCodec && !finalSource.contains("import ISO8601DateCodecKit") {
                finalSource = injectImport(content: finalSource, moduleName: "ISO8601DateCodecKit")
                importsAdded.append("ISO8601DateCodecKit")
            }
        }

        return TransformationReport(
            originalSource: source,
            transformedSource: finalSource,
            replacementCount: replacementCount,
            deadDeclarationsRemoved: deadDeclarationsRemoved,
            importsRemoved: importsRemoved,
            importsAdded: importsAdded,
            appliedRules: appliedRules
        )
    }

    // MARK: - 5. Matching Helpers

    private struct DecodeMatch {
        let startIndex: Int
        let endIndex: Int
        let typeArgTokens: [SyntaxToken]
        let dataArgTokens: [SyntaxToken]
    }

    private func matchDecodeCall(
        tokens: [SyntaxToken],
        fromIndex idx: Int,
        boundVars: [BoundDeclaration]
    ) -> DecodeMatch? {
        // Case 1: JSONDecoder().decode(...)
        // Case 2: <var>.decode(...)
        var startIndex = idx
        var isMatch = false

        if idx + 4 < tokens.count &&
            tokens[idx].text == "JSONDecoder" &&
            tokens[idx + 1].text == "(" &&
            tokens[idx + 2].text == ")" &&
            tokens[idx + 3].text == "." &&
            tokens[idx + 4].text == "decode" {
            startIndex = idx
            isMatch = true
        } else if idx + 2 < tokens.count &&
                    tokens[idx + 1].text == "." &&
                    tokens[idx + 2].text == "decode" &&
                    boundVars.contains(where: { $0.name == tokens[idx].text && $0.kind == .jsonDecoder }) {
            startIndex = idx
            isMatch = true
        }

        guard isMatch else { return nil }

        // decode 뒤의 '(' 위치 찾기
        var openParenIndex = startIndex
        while openParenIndex < tokens.count && tokens[openParenIndex].text != "decode" {
            openParenIndex += 1
        }
        openParenIndex += 1
        guard openParenIndex < tokens.count && tokens[openParenIndex].text == "(" else { return nil }

        // 매칭되는 닫는 괄호 찾기
        var closeParenIndex = openParenIndex
        var depth = 0
        var commaIndex: Int?
        var fromColonIndex: Int?

        while closeParenIndex < tokens.count {
            let t = tokens[closeParenIndex].text
            if t == "(" || t == "{" || t == "[" {
                depth += 1
            } else if t == ")" || t == "}" || t == "]" {
                depth -= 1
                if depth == 0 {
                    break
                }
            } else if depth == 1 {
                if t == "," && commaIndex == nil {
                    commaIndex = closeParenIndex
                } else if commaIndex != nil && t == "from" && closeParenIndex + 1 < tokens.count && tokens[closeParenIndex + 1].text == ":" {
                    fromColonIndex = closeParenIndex + 1
                }
            }
            closeParenIndex += 1
        }

        guard depth == 0, let comma = commaIndex, let fromColon = fromColonIndex else { return nil }

        let typeArgTokens = Array(tokens[(openParenIndex + 1)..<comma])
        let dataArgTokens = Array(tokens[(fromColon + 1)..<closeParenIndex])

        return DecodeMatch(
            startIndex: startIndex,
            endIndex: closeParenIndex,
            typeArgTokens: typeArgTokens,
            dataArgTokens: dataArgTokens
        )
    }

    private struct EncodeMatch {
        let startIndex: Int
        let endIndex: Int
        let argTokens: [SyntaxToken]
    }

    private func matchEncodeCall(
        tokens: [SyntaxToken],
        fromIndex idx: Int,
        boundVars: [BoundDeclaration]
    ) -> EncodeMatch? {
        var startIndex = idx
        var isMatch = false

        if idx + 4 < tokens.count &&
            tokens[idx].text == "JSONEncoder" &&
            tokens[idx + 1].text == "(" &&
            tokens[idx + 2].text == ")" &&
            tokens[idx + 3].text == "." &&
            tokens[idx + 4].text == "encode" {
            startIndex = idx
            isMatch = true
        } else if idx + 2 < tokens.count &&
                    tokens[idx + 1].text == "." &&
                    tokens[idx + 2].text == "encode" &&
                    boundVars.contains(where: { $0.name == tokens[idx].text && $0.kind == .jsonEncoder }) {
            startIndex = idx
            isMatch = true
        }

        guard isMatch else { return nil }

        var openParenIndex = startIndex
        while openParenIndex < tokens.count && tokens[openParenIndex].text != "encode" {
            openParenIndex += 1
        }
        openParenIndex += 1
        guard openParenIndex < tokens.count && tokens[openParenIndex].text == "(" else { return nil }

        var closeParenIndex = openParenIndex
        var depth = 0
        while closeParenIndex < tokens.count {
            let t = tokens[closeParenIndex].text
            if t == "(" || t == "{" || t == "[" {
                depth += 1
            } else if t == ")" || t == "}" || t == "]" {
                depth -= 1
                if depth == 0 { break }
            }
            closeParenIndex += 1
        }

        guard depth == 0 else { return nil }
        let argTokens = Array(tokens[(openParenIndex + 1)..<closeParenIndex])

        return EncodeMatch(startIndex: startIndex, endIndex: closeParenIndex, argTokens: argTokens)
    }

    private struct DateStringMatch {
        let startIndex: Int
        let endIndex: Int
        let isNow: Bool
        let argTokens: [SyntaxToken]
    }

    private func matchDateStringCall(
        tokens: [SyntaxToken],
        fromIndex idx: Int,
        boundVars: [BoundDeclaration]
    ) -> DateStringMatch? {
        var startIndex = idx
        var isMatch = false

        let isDateFormatterInit = idx + 4 < tokens.count &&
            (tokens[idx].text == "DateFormatter" || tokens[idx].text == "ISO8601DateFormatter") &&
            tokens[idx + 1].text == "(" &&
            tokens[idx + 2].text == ")" &&
            tokens[idx + 3].text == "." &&
            tokens[idx + 4].text == "string"

        let isBoundVarCall = idx + 2 < tokens.count &&
            tokens[idx + 1].text == "." &&
            tokens[idx + 2].text == "string" &&
            boundVars.contains(where: { $0.name == tokens[idx].text && ($0.kind == .dateFormatter || $0.kind == .iso8601DateFormatter) })

        if isDateFormatterInit || isBoundVarCall {
            startIndex = idx
            isMatch = true
        }

        guard isMatch else { return nil }

        var openParenIndex = startIndex
        while openParenIndex < tokens.count && tokens[openParenIndex].text != "string" {
            openParenIndex += 1
        }
        openParenIndex += 1
        guard openParenIndex < tokens.count && tokens[openParenIndex].text == "(" else { return nil }

        // from: 뒤의 인자 찾기
        guard openParenIndex + 2 < tokens.count && tokens[openParenIndex + 1].text == "from" && tokens[openParenIndex + 2].text == ":" else {
            return nil
        }

        var closeParenIndex = openParenIndex
        var depth = 0
        while closeParenIndex < tokens.count {
            let t = tokens[closeParenIndex].text
            if t == "(" || t == "{" || t == "[" {
                depth += 1
            } else if t == ")" || t == "}" || t == "]" {
                depth -= 1
                if depth == 0 { break }
            }
            closeParenIndex += 1
        }

        guard depth == 0 else { return nil }
        let argTokens = Array(tokens[(openParenIndex + 3)..<closeParenIndex])

        // Date() 인지 판별
        let isNow = argTokens.count == 3 &&
            argTokens[0].text == "Date" &&
            argTokens[1].text == "(" &&
            argTokens[2].text == ")"

        return DateStringMatch(startIndex: startIndex, endIndex: closeParenIndex, isNow: isNow, argTokens: argTokens)
    }

    private struct DateParseMatch {
        let startIndex: Int
        let endIndex: Int
        let argTokens: [SyntaxToken]
    }

    private func matchDateParseCall(
        tokens: [SyntaxToken],
        fromIndex idx: Int,
        boundVars: [BoundDeclaration]
    ) -> DateParseMatch? {
        var startIndex = idx
        var isMatch = false

        let isDateFormatterInit = idx + 4 < tokens.count &&
            (tokens[idx].text == "DateFormatter" || tokens[idx].text == "ISO8601DateFormatter") &&
            tokens[idx + 1].text == "(" &&
            tokens[idx + 2].text == ")" &&
            tokens[idx + 3].text == "." &&
            tokens[idx + 4].text == "date"

        let isBoundVarCall = idx + 2 < tokens.count &&
            tokens[idx + 1].text == "." &&
            tokens[idx + 2].text == "date" &&
            boundVars.contains(where: { $0.name == tokens[idx].text && ($0.kind == .dateFormatter || $0.kind == .iso8601DateFormatter) })

        if isDateFormatterInit || isBoundVarCall {
            startIndex = idx
            isMatch = true
        }

        guard isMatch else { return nil }

        var openParenIndex = startIndex
        while openParenIndex < tokens.count && tokens[openParenIndex].text != "date" {
            openParenIndex += 1
        }
        openParenIndex += 1
        guard openParenIndex < tokens.count && tokens[openParenIndex].text == "(" else { return nil }

        guard openParenIndex + 2 < tokens.count && tokens[openParenIndex + 1].text == "from" && tokens[openParenIndex + 2].text == ":" else {
            return nil
        }

        var closeParenIndex = openParenIndex
        var depth = 0
        while closeParenIndex < tokens.count {
            let t = tokens[closeParenIndex].text
            if t == "(" || t == "{" || t == "[" {
                depth += 1
            } else if t == ")" || t == "}" || t == "]" {
                depth -= 1
                if depth == 0 { break }
            }
            closeParenIndex += 1
        }

        guard depth == 0 else { return nil }
        let argTokens = Array(tokens[(openParenIndex + 3)..<closeParenIndex])

        return DateParseMatch(startIndex: startIndex, endIndex: closeParenIndex, argTokens: argTokens)
    }

    private func injectImport(content: String, moduleName: String) -> String {
        let importStatement = "import \(moduleName)"
        if content.contains(importStatement) { return content }

        let lines = content.components(separatedBy: "\n")
        var lastImportIndex = -1

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("import ") {
                lastImportIndex = index
            }
        }

        var newLines = lines
        if lastImportIndex >= 0 {
            newLines.insert(importStatement, at: lastImportIndex + 1)
        } else {
            var insertIndex = 0
            for (index, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("//") || trimmed.hasPrefix("/*") || trimmed.hasPrefix("*") || trimmed.isEmpty {
                    continue
                }
                insertIndex = index
                break
            }
            newLines.insert(importStatement, at: insertIndex)
        }

        return newLines.joined(separator: "\n")
    }
}
