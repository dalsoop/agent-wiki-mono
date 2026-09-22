import Foundation

public struct MarkdownSearchMatch: Codable, Sendable, Equatable {
    public let file: String
    public let lineNumber: Int
    public let lineContent: String
    public let snippet: String
    public let match: String

    public init(
        file: String,
        lineNumber: Int,
        lineContent: String,
        snippet: String,
        match: String
    ) {
        self.file = file
        self.lineNumber = lineNumber
        self.lineContent = lineContent
        self.snippet = snippet
        self.match = match
    }
}

public struct MarkdownSearchResult: Codable, Sendable, Equatable {
    public let query: String
    public let isRegex: Bool
    public let totalMatches: Int
    public let fileCount: Int
    public let matches: [MarkdownSearchMatch]

    public init(
        query: String,
        isRegex: Bool,
        matches: [MarkdownSearchMatch]
    ) {
        self.query = query
        self.isRegex = isRegex
        self.totalMatches = matches.count
        self.fileCount = Set(matches.map(\.file)).count
        self.matches = matches
    }
}

public protocol MarkdownSearchEngine: Sendable {
    func search(
        query: String,
        isRegex: Bool,
        caseInsensitive: Bool,
        in files: [URL],
        relativeTo root: URL?
    ) -> MarkdownSearchResult
}

public extension MarkdownSearchEngine {
    func search(
        query: String,
        isRegex: Bool = false,
        caseInsensitive: Bool = false,
        in files: [URL],
        relativeTo root: URL? = nil
    ) -> MarkdownSearchResult {
        search(
            query: query,
            isRegex: isRegex,
            caseInsensitive: caseInsensitive,
            in: files,
            relativeTo: root
        )
    }
}

public struct DefaultMarkdownSearchEngine: MarkdownSearchEngine {
    public init() {}

    public func search(
        query: String,
        isRegex: Bool = false,
        caseInsensitive: Bool = false,
        in files: [URL],
        relativeTo root: URL? = nil
    ) -> MarkdownSearchResult {
        Self.search(
            query: query,
            isRegex: isRegex,
            caseInsensitive: caseInsensitive,
            in: files,
            relativeTo: root
        )
    }

    public static func search(
        query: String,
        isRegex: Bool = false,
        caseInsensitive: Bool = false,
        in files: [URL],
        relativeTo root: URL? = nil
    ) -> MarkdownSearchResult {
        let regex = compiledRegex(query: query, isRegex: isRegex, caseInsensitive: caseInsensitive)
        if isRegex && regex == nil {
            return MarkdownSearchResult(query: query, isRegex: true, matches: [])
        }
        let matches = files.flatMap { fileURL in
            matchesInFile(
                fileURL,
                query: query,
                regex: regex,
                caseInsensitive: caseInsensitive,
                relativeTo: root
            )
        }
        return MarkdownSearchResult(query: query, isRegex: isRegex, matches: matches)
    }

    private static func compiledRegex(
        query: String,
        isRegex: Bool,
        caseInsensitive: Bool
    ) -> NSRegularExpression? {
        guard isRegex else { return nil }
        let options: NSRegularExpression.Options = caseInsensitive ? [.caseInsensitive] : []
        do {
            return try NSRegularExpression(pattern: query, options: options)
        } catch {
            return nil
        }
    }

    private static func matchesInFile(
        _ fileURL: URL,
        query: String,
        regex: NSRegularExpression?,
        caseInsensitive: Bool,
        relativeTo root: URL?
    ) -> [MarkdownSearchMatch] {
        let content: String
        do {
            content = try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            return []
        }
        let compareOptions: NSString.CompareOptions = caseInsensitive ? [.caseInsensitive] : []
        if regex == nil, content.range(of: query, options: compareOptions) == nil {
            return []
        }
        let filePath = relativePath(of: fileURL, to: root)
        return content.components(separatedBy: "\n").enumerated().flatMap { idx, line in
            matchesInLine(
                line,
                lineNumber: idx + 1,
                filePath: filePath,
                query: query,
                regex: regex,
                compareOptions: compareOptions
            )
        }
    }

    private static func matchesInLine(
        _ line: String,
        lineNumber: Int,
        filePath: String,
        query: String,
        regex: NSRegularExpression?,
        compareOptions: NSString.CompareOptions
    ) -> [MarkdownSearchMatch] {
        if let regex {
            return regexMatches(
                line,
                lineNumber: lineNumber,
                filePath: filePath,
                regex: regex
            )
        }
        return literalMatches(
            line,
            lineNumber: lineNumber,
            filePath: filePath,
            query: query,
            compareOptions: compareOptions
        )
    }

    private static func regexMatches(
        _ line: String,
        lineNumber: Int,
        filePath: String,
        regex: NSRegularExpression
    ) -> [MarkdownSearchMatch] {
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        return regex.matches(in: line, options: [], range: range).compactMap { m in
            guard let r = Range(m.range, in: line) else { return nil }
            return makeMatch(filePath: filePath, lineNumber: lineNumber, line: line, match: String(line[r]))
        }
    }

    private static func literalMatches(
        _ line: String,
        lineNumber: Int,
        filePath: String,
        query: String,
        compareOptions: NSString.CompareOptions
    ) -> [MarkdownSearchMatch] {
        var searchRange = line.startIndex..<line.endIndex
        var matches: [MarkdownSearchMatch] = []
        while let found = line.range(of: query, options: compareOptions, range: searchRange) {
            matches.append(
                makeMatch(filePath: filePath, lineNumber: lineNumber, line: line, match: String(line[found]))
            )
            searchRange = found.upperBound..<line.endIndex
        }
        return matches
    }

    private static func makeMatch(
        filePath: String,
        lineNumber: Int,
        line: String,
        match: String
    ) -> MarkdownSearchMatch {
        MarkdownSearchMatch(
            file: filePath,
            lineNumber: lineNumber,
            lineContent: line,
            snippet: line.trimmingCharacters(in: .whitespaces),
            match: match
        )
    }

    private static func relativePath(of fileURL: URL, to root: URL?) -> String {
        guard let root else { return fileURL.path }
        let rootPrefix = root.standardizedFileURL.path + "/"
        let fullPath = fileURL.standardizedFileURL.path
        guard fullPath.hasPrefix(rootPrefix) else { return fileURL.path }
        return String(fullPath.dropFirst(rootPrefix.count))
    }
}
