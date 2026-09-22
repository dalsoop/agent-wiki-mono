import Foundation

/// SwiftUI View 소스 코드를 패치하여 AppErrorKit 바인딩을 주입하는 도구.
/// 표면 패리티 억제 주석은 `suppressSurfaceParity`가 true이고 유효 UUID backlog일 때만 넣는다.
public enum UniversalViewPatcher {

    /// View 패치 결과
    public struct Result: Sendable, Equatable {
        public let originalSource: String
        public let patchedSource: String
        public let isModified: Bool
        public let injectedParitySuppression: Bool
        public let injectedAppErrorHandling: Bool
        public let addedImports: [String]

        public init(
            originalSource: String,
            patchedSource: String,
            isModified: Bool,
            injectedParitySuppression: Bool,
            injectedAppErrorHandling: Bool,
            addedImports: [String]
        ) {
            self.originalSource = originalSource
            self.patchedSource = patchedSource
            self.isModified = isModified
            self.injectedParitySuppression = injectedParitySuppression
            self.injectedAppErrorHandling = injectedAppErrorHandling
            self.addedImports = addedImports
        }
    }

    private static let uuidBacklogPattern = makeRegex(
        #"backlog#[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"#
    )

    private static func makeRegex(_ pattern: String) -> NSRegularExpression? {
        do {
            return try NSRegularExpression(pattern: pattern)
        } catch {
            return nil
        }
    }

    private static let viewDeclarationPattern = makeRegex(#"\b(?:struct|class)\s+\w+\s*:\s*[^\{]*\bView\b"#)

    private static let modifierAnchorPatterns: [NSRegularExpression] = {
        let patterns = [
            #"((\.task\s*\{[^\}]*\})|(\.frame\([^\)]*\)))(\n\s*\})"#
        ]
        return patterns.compactMap { makeRegex($0) }
    }()

    /// View 소스 코드를 패치합니다.
    public static func patch(
        source: String,
        options: UniversalErrorPatcher.Options = .init()
    ) -> Result {
        let (sourceAfterSuppression, didSuppress) = applyParitySuppressionIfNeeded(
            source: source,
            options: options
        )

        let (sourceAfterImports, addedImports) = applyAppErrorKitImportIfNeeded(
            source: sourceAfterSuppression,
            options: options
        )

        let (finalSource, didInjectModifier) = applyErrorModifierIfNeeded(
            source: sourceAfterImports,
            options: options
        )

        return Result(
            originalSource: source,
            patchedSource: finalSource,
            isModified: finalSource != source,
            injectedParitySuppression: didSuppress,
            injectedAppErrorHandling: didInjectModifier,
            addedImports: addedImports
        )
    }

    // MARK: - 정적 분석 헬퍼

    /// 소스 내에 유효 UUID backlog를 가진 표면 패리티 억제 주석이 있는지 검사합니다.
    public static func hasParitySuppression(in content: String) -> Bool {
        let lines = content.components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let isComment = trimmed.hasPrefix("//") || trimmed.hasPrefix("/*")
            guard isComment else { continue }
            if isValidParitySuppressionComment(trimmed) {
                return true
            }
        }
        return false
    }

    /// 표면 패리티 억제 주석은 36자리 UUID backlog 식별자가 있어야 유효하다. 숫자 가짜 ID는 거부한다.
    public static func isValidParitySuppressionComment(_ comment: String) -> Bool {
        let trimmed = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let lower = trimmed.lowercased()
        guard lower.contains("parity-suppress") else { return false }
        let range = NSRange(location: 0, length: (trimmed as NSString).length)
        return uuidBacklogPattern?.firstMatch(in: trimmed, options: [], range: range) != nil
    }

    /// 파일명이 Screen View 인지 검사합니다.
    public static func isScreenView(fileName: String, content: String, relativePath: String = "") -> Bool {
        guard isCandidateViewName(fileName: fileName, relativePath: relativePath) else {
            return false
        }
        guard !fileName.contains("Preview") && !fileName.contains("Tests") else {
            return false
        }

        let range = NSRange(location: 0, length: (content as NSString).length)
        return viewDeclarationPattern?.firstMatch(in: content, options: [], range: range) != nil
    }

    private static let candidateSuffixes = ["Screen.swift", "View.swift"]

    private static func isCandidateViewName(fileName: String, relativePath: String) -> Bool {
        candidateSuffixes.contains(where: fileName.hasSuffix) || relativePath.contains("Views/")
    }

    // MARK: - 변환 단계 헬퍼

    private static func applyParitySuppressionIfNeeded(
        source: String,
        options: UniversalErrorPatcher.Options
    ) -> (String, Bool) {
        guard options.suppressSurfaceParity,
              !hasParitySuppression(in: source),
              isValidParitySuppressionComment(options.paritySuppressionComment) else {
            return (source, false)
        }
        let trimmed = options.paritySuppressionComment.trimmingCharacters(in: .whitespacesAndNewlines)
        let comment = trimmed.hasPrefix("//") || trimmed.hasPrefix("/*") ? trimmed : "// " + trimmed
        let updated = source.isEmpty ? comment + "\n" : comment + "\n" + source
        return (updated, true)
    }

    private static func applyAppErrorKitImportIfNeeded(
        source: String,
        options: UniversalErrorPatcher.Options
    ) -> (String, [String]) {
        guard options.ensureAppErrorKitImport else {
            return (source, [])
        }
        let stripped = SourceTransformerHelper.stripCommentsAndStrings(source)
        guard !SourceTransformerHelper.hasImport("AppErrorKit", in: stripped) else {
            return (source, [])
        }
        return SourceTransformerHelper.injectImports(["AppErrorKit"], into: source)
    }

    private static func applyErrorModifierIfNeeded(
        source: String,
        options: UniversalErrorPatcher.Options
    ) -> (String, Bool) {
        guard let binding = options.viewErrorBinding,
              !source.contains(".appErrorHandling("),
              source.contains("var body: some View") else {
            return (source, false)
        }

        let modifier = "\n        .appErrorHandling(error: \(binding))"
        let nsSource = source as NSString
        let fullRange = NSRange(location: 0, length: nsSource.length)

        for pattern in modifierAnchorPatterns {
            guard let match = pattern.firstMatch(in: source, range: fullRange) else {
                continue
            }
            let targetRange = match.range(at: 1)
            let insertPos = targetRange.location + targetRange.length
            var result = source
            let idx = source.index(source.startIndex, offsetBy: insertPos)
            result.insert(contentsOf: modifier, at: idx)
            return (result, true)
        }

        return (source, false)
    }
}
