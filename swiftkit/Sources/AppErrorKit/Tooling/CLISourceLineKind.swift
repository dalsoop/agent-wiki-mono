import Foundation

enum CLISourceLineKind {
    case ifDirective
    case prelude
    case fileScope
    case body

    static func classify(_ masked: String) -> CLISourceLineKind? {
        if masked.hasPrefix("#if") { return .ifDirective }
        if isPreludeMaskedLine(masked) { return .prelude }
        return declarationOrBody(masked)
    }

    static func isConditionalDirective(_ masked: String) -> Bool {
        conditionalDirectives.contains { masked.hasPrefix($0) }
    }
}

private extension CLISourceLineKind {
    static let preludePrefixes = ["//", "/*", "*", "#!"]
    static let accessOrImportModifiers: Set<String> = [
        "public", "package", "internal", "fileprivate", "private"
    ]
    static let fileScopeDeclKeywords: Set<String> = [
        "struct", "class", "enum", "actor", "protocol", "extension",
        "func", "typealias", "associatedtype", "operator", "precedencegroup", "macro"
    ]
    static let accessAndDeclModifiers: Set<String> = [
        "public", "private", "internal", "fileprivate", "open", "package",
        "final", "indirect", "nonisolated", "consuming", "borrowing", "distributed",
        "dynamic", "optional", "required", "static", "override", "convenience",
        "mutating", "nonmutating", "isolated", "lazy", "weak", "unowned"
    ]
    static let statementKeywords: Set<String> = [
        "let", "var", "if", "guard", "for", "while", "repeat", "switch", "do",
        "defer", "return", "throw", "break", "continue", "fallthrough", "await",
        "try", "print", "Task"
    ]
    static let poundDeclPrefixes = ["#warning", "#error", "#sourceLocation"]
    static let conditionalDirectives = ["#if", "#elseif", "#else", "#endif"]

    static func declarationOrBody(_ masked: String) -> CLISourceLineKind? {
        if isFileScopeDeclarationStart(masked) { return .fileScope }
        if isBodyStart(masked) { return .body }
        return nil
    }

    static func isPreludeMaskedLine(_ masked: String) -> Bool {
        isBlankOrCommentPrelude(masked) || isImportOrEntryGate(masked)
    }

    static func isBlankOrCommentPrelude(_ masked: String) -> Bool {
        if masked.isEmpty { return true }
        return preludePrefixes.contains { masked.hasPrefix($0) }
    }

    static func isImportOrEntryGate(_ masked: String) -> Bool {
        isImportLine(masked) || masked.contains("GujoManaged.exitIfNotEntitledSync()")
    }

    static func isImportLine(_ masked: String) -> Bool {
        let tokens = masked.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard let importIndex = tokens.firstIndex(of: "import") else {
            return false
        }
        let prefix = tokens[..<importIndex]
        return prefix.allSatisfy(isImportPrefixToken)
    }

    static func isImportPrefixToken(_ token: String) -> Bool {
        token.hasPrefix("@") || accessOrImportModifiers.contains(token)
    }

    static func isFileScopeDeclarationStart(_ masked: String) -> Bool {
        if masked.hasPrefix("@") { return true }
        if isPoundDeclaration(masked) { return true }
        return isDeclKeywordLine(masked)
    }

    static func isPoundDeclaration(_ masked: String) -> Bool {
        poundDeclPrefixes.contains { masked.hasPrefix($0) }
    }

    static func isDeclKeywordLine(_ masked: String) -> Bool {
        guard let first = leadingTokens(masked).first else { return false }
        return fileScopeDeclKeywords.contains(identifierPrefix(first))
    }

    static func isBodyStart(_ masked: String) -> Bool {
        guard let first = leadingTokens(masked).first else { return false }
        return isStatementIdent(identifierPrefix(first), raw: first)
    }

    static func isStatementIdent(_ ident: String, raw: String) -> Bool {
        if statementKeywords.contains(ident) { return true }
        if isTryKeyword(raw) { return true }
        return isCallLikeStatement(ident, raw: raw)
    }

    static func isTryKeyword(_ raw: String) -> Bool {
        raw == "try" || raw.hasPrefix("try")
    }

    static func isCallLikeStatement(_ ident: String, raw: String) -> Bool {
        if isNonStatementPrefix(raw, ident: ident) { return false }
        return ident.first?.isLetter == true || ident == "_"
    }

    static func isNonStatementPrefix(_ raw: String, ident: String) -> Bool {
        if raw.hasPrefix("#") { return true }
        if raw.hasPrefix("@") { return true }
        return fileScopeDeclKeywords.contains(ident)
    }

    static func identifierPrefix(_ token: String) -> String {
        var result = ""
        for ch in token {
            guard isIdentChar(ch, prefix: result) else { break }
            result.append(ch)
        }
        return result
    }

    static func isIdentChar(_ ch: Character, prefix: String) -> Bool {
        if ch.isLetter { return true }
        if ch == "_" { return true }
        return !prefix.isEmpty && ch.isNumber
    }

    static func leadingTokens(_ masked: String) -> [String] {
        var tokens: [String] = []
        for raw in masked.split(whereSeparator: { $0.isWhitespace }).map(String.init) {
            if isSkippedLeadingToken(raw) { continue }
            tokens.append(raw)
        }
        return tokens
    }

    static func isSkippedLeadingToken(_ raw: String) -> Bool {
        raw.hasPrefix("@") || accessAndDeclModifiers.contains(raw)
    }
}
