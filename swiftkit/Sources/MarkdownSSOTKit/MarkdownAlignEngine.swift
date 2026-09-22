import Foundation

public struct AlignMismatch: Codable, Sendable, Equatable {
    public let file: String
    public let lineNumber: Int
    public let originalLine: String
    public let proposedLine: String
    public let pattern: String
    public let replacement: String

    public init(
        file: String,
        lineNumber: Int,
        originalLine: String,
        proposedLine: String,
        pattern: String,
        replacement: String
    ) {
        self.file = file
        self.lineNumber = lineNumber
        self.originalLine = originalLine
        self.proposedLine = proposedLine
        self.pattern = pattern
        self.replacement = replacement
    }
}

public struct FileAlignDiff: Codable, Sendable, Equatable {
    public let file: String
    public let fileURL: URL
    public let originalContent: String
    public let alignedContent: String
    public let mismatches: [AlignMismatch]
    public var hasChanges: Bool { originalContent != alignedContent }

    public init(
        file: String,
        fileURL: URL,
        originalContent: String,
        alignedContent: String,
        mismatches: [AlignMismatch]
    ) {
        self.file = file
        self.fileURL = fileURL
        self.originalContent = originalContent
        self.alignedContent = alignedContent
        self.mismatches = mismatches
    }
}

public struct AlignReport: Codable, Sendable, Equatable {
    public let totalFilesScanned: Int
    public let filesWithMismatches: Int
    public let totalMismatches: Int
    public let diffs: [FileAlignDiff]
    public let applied: Bool
    public let ledgerIdentifier: String?

    public init(
        totalFilesScanned: Int,
        diffs: [FileAlignDiff],
        applied: Bool,
        ledgerIdentifier: String? = nil
    ) {
        self.totalFilesScanned = totalFilesScanned
        self.diffs = diffs
        self.filesWithMismatches = diffs.filter(\.hasChanges).count
        self.totalMismatches = diffs.reduce(0) { $0 + $1.mismatches.count }
        self.applied = applied
        self.ledgerIdentifier = ledgerIdentifier
    }
}

/// 구체 타입에 결합되지 않고 `some AlignRuleProvider`와 `some MarkdownFileCollector`에만
/// 의존하는 다형적 마크다운 SSOT 정렬 엔진.
public struct MarkdownAlignEngine: Sendable {
    public init() {}

    public static func scanAndAlign(
        files: [URL],
        rules: some AlignRuleProvider,
        relativeTo root: URL? = nil,
        apply: Bool = false
    ) throws -> AlignReport {
        let replacements = rules.replacementRules()
        var diffs: [FileAlignDiff] = []
        for fileURL in files {
            guard let diff = try alignOneFile(
                fileURL,
                replacements: replacements,
                relativeTo: root,
                apply: apply
            ) else { continue }
            diffs.append(diff)
        }
        return AlignReport(
            totalFilesScanned: files.count,
            diffs: diffs,
            applied: apply,
            ledgerIdentifier: rules.ledgerIdentifier
        )
    }

    public static func scanAndAlign(
        under root: URL,
        collector: some MarkdownFileCollector = DefaultMarkdownFileCollector(),
        rules: some AlignRuleProvider,
        limit: Int? = nil,
        apply: Bool = false
    ) throws -> AlignReport {
        let files = collector.collect(under: root, limit: limit)
        return try scanAndAlign(files: files, rules: rules, relativeTo: root, apply: apply)
    }

    private static func alignOneFile(
        _ fileURL: URL,
        replacements: [(from: String, to: String)],
        relativeTo root: URL?,
        apply: Bool
    ) throws -> FileAlignDiff? {
        let content: String
        do {
            content = try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            return nil
        }
        guard contentContainsAnyPattern(content, replacements: replacements) else {
            return nil
        }
        let filePath = relativePath(of: fileURL, to: root)
        let (aligned, mismatches) = applyReplacements(
            content: content,
            filePath: filePath,
            replacements: replacements
        )
        let diff = FileAlignDiff(
            file: filePath,
            fileURL: fileURL,
            originalContent: content,
            alignedContent: aligned,
            mismatches: mismatches
        )
        guard diff.hasChanges else { return nil }
        if apply {
            try Data(aligned.utf8).write(to: fileURL, options: .atomic)
        }
        return diff
    }

    private static func contentContainsAnyPattern(
        _ content: String,
        replacements: [(from: String, to: String)]
    ) -> Bool {
        replacements.contains { from, _ in
            (content as NSString).range(of: from, options: .literal).location != NSNotFound
        }
    }

    private static func applyReplacements(
        content: String,
        filePath: String,
        replacements: [(from: String, to: String)]
    ) -> (String, [AlignMismatch]) {
        let lines = content.components(separatedBy: "\n")
        var mismatches: [AlignMismatch] = []
        let newLines = lines.enumerated().map { idx, line in
            rewriteLine(
                line,
                lineNumber: idx + 1,
                filePath: filePath,
                replacements: replacements,
                mismatches: &mismatches
            )
        }
        return (newLines.joined(separator: "\n"), mismatches)
    }

    private static func rewriteLine(
        _ line: String,
        lineNumber: Int,
        filePath: String,
        replacements: [(from: String, to: String)],
        mismatches: inout [AlignMismatch]
    ) -> String {
        var modified = line
        for (from, to) in replacements {
            guard (modified as NSString).range(of: from, options: .literal).location != NSNotFound else {
                continue
            }
            let next = modified.replacingOccurrences(of: from, with: to, options: .literal)
            mismatches.append(
                AlignMismatch(
                    file: filePath,
                    lineNumber: lineNumber,
                    originalLine: line,
                    proposedLine: next,
                    pattern: from,
                    replacement: to
                )
            )
            modified = next
        }
        return modified
    }

    private static func relativePath(of fileURL: URL, to root: URL?) -> String {
        guard let root else { return fileURL.path }
        let rootPrefix = root.standardizedFileURL.path + "/"
        let fullPath = fileURL.standardizedFileURL.path
        guard fullPath.hasPrefix(rootPrefix) else { return fileURL.path }
        return String(fullPath.dropFirst(rootPrefix.count))
    }
}
