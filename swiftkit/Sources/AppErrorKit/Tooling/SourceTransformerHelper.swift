import Foundation

/// Swift 소스 코드 변환 및 정적 검사를 위한 내부 헬퍼.
enum SourceTransformerHelper {

    private static func makeRegex(_ pattern: String) -> NSRegularExpression? {
        do {
            return try NSRegularExpression(pattern: pattern)
        } catch {
            return nil
        }
    }

    private static let singleInstancePattern = makeRegex(#"\b(SingleInstanceCLI|SingleInstance)\b"#)
    private static let runWithUniversalErrorPattern = makeRegex(#"runWithUniversalError\s*\{"#)

    private static let nameExtractionRegexes: [NSRegularExpression] = {
        let patterns = [
            #"SingleInstanceCLI\.exitIfAlreadyRunning\(\s*name:\s*"([^"]+)""#,
            #"CLIMarketingVersion\.printLine\(\s*name:\s*"([^"]+)""#,
            #"AgentCLIApp\(\s*slug:\s*"([^"]+)""#,
            #"HealthPulse\.publish\(\s*app:\s*"([^"]+)""#,
            #"StateMirror\.onTerminate\(\s*app:\s*"([^"]+)""#
        ]
        return patterns.compactMap { makeRegex($0) }
    }()

    private static let singleInstanceTokens = [
        "SingleInstanceCLI.exitIfAlreadyRunning",
        "SingleInstance.exitIfAlreadyRunning",
        "SingleInstanceCLI.acquire"
    ]

    /// SingleInstanceCLI 또는 SingleInstance 가드 토큰 존재 여부
    static func hasSingleInstanceGuard(in code: String) -> Bool {
        guard !singleInstanceTokens.contains(where: code.contains) else { return true }
        let range = NSRange(location: 0, length: (code as NSString).length)
        return singleInstancePattern?.firstMatch(in: code, options: [], range: range) != nil
    }

    /// 종료 훅 또는 teardown 존재 여부
    static func hasTerminationHook(in code: String) -> Bool {
        code.contains("onTerminate") || code.contains("teardown")
    }

    /// 실제 `runWithUniversalError {` 호출. 주석·문자열 리터럴은 호출이 아니다.
    static func hasRunWithUniversalErrorCall(in source: String) -> Bool {
        firstRunWithUniversalErrorCallRange(in: source) != nil
    }

    /// import <module> 존재 여부
    static func hasImport(_ moduleName: String, in code: String) -> Bool {
        let pattern = #"(?m)^\s*import\s+(?:typealias\s+|struct\s+|class\s+|enum\s+|protocol\s+|let\s+|var\s+|func\s+)?\#(moduleName)\b"#
        guard let regex = makeRegex(pattern) else {
            return code.contains("import \(moduleName)")
        }
        let range = NSRange(location: 0, length: (code as NSString).length)
        return regex.firstMatch(in: code, options: [], range: range) != nil
    }

    /// 소스 내 주석 및 문자열에서 앱 이름 추출
    static func extractAppName(from source: String) -> String? {
        let nsSource = source as NSString
        let fullRange = NSRange(location: 0, length: nsSource.length)

        for regex in nameExtractionRegexes {
            guard let match = regex.firstMatch(in: source, range: fullRange), match.numberOfRanges > 1 else {
                continue
            }
            return nsSource.substring(with: match.range(at: 1))
        }
        return nil
    }

    /// 기존 import 목록 뒤에 신규 모듈 import 문을 주입
    static func injectImports(_ modules: [String], into source: String) -> (String, [String]) {
        let neededModules = modules.filter { !hasImport($0, in: source) }
        guard !neededModules.isEmpty else { return (source, []) }

        let lines = source.components(separatedBy: "\n")
        let (lastImportIndex, firstCodeIndex) = locateImportIndices(lines: lines)
        let importStatements = neededModules.map { "import \($0)" }
        var newLines = lines

        if lastImportIndex != -1 {
            newLines.insert(contentsOf: importStatements, at: lastImportIndex + 1)
        } else {
            let targetIdx = firstCodeIndex != -1 ? firstCodeIndex : 0
            newLines.insert(contentsOf: importStatements + [""], at: targetIdx)
        }

        return (newLines.joined(separator: "\n"), neededModules)
    }

    private static func locateImportIndices(lines: [String]) -> (lastImport: Int, firstCode: Int) {
        var lastImport = -1
        var firstCode = -1
        for (idx, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("import ") {
                lastImport = idx
            } else if isCodeLine(trimmed) && firstCode == -1 {
                firstCode = idx
            }
        }
        return (lastImport, firstCode)
    }

    /// 이미 존재하는 runWithUniversalError 블록 시작 부분에 가드 주입
    static func injectGuardsIntoBlock(source: String, guards: [String]) -> String {
        guard !guards.isEmpty else { return source }
        guard let callRange = firstRunWithUniversalErrorCallRange(in: source) else {
            return source
        }
        let guardBlock = "\n" + guards.joined(separator: "\n")
        var result = source
        result.insert(contentsOf: guardBlock, at: callRange.upperBound)
        return result
    }

    /// UTF-16 `NSRange`를 Character offset으로 쓰지 않고, 마스킹된 소스에서 매칭한 뒤
    /// 원문의 `String.Index` 로 되돌린다. 문자열 리터럴은 호출이 아니다.
    private static func firstRunWithUniversalErrorCallRange(in source: String) -> Range<String.Index>? {
        let masked = stripCommentsAndStrings(source)
        guard (masked as NSString).length == (source as NSString).length else {
            return nil
        }
        let range = NSRange(location: 0, length: (masked as NSString).length)
        guard let match = runWithUniversalErrorPattern?.firstMatch(in: masked, options: [], range: range) else {
            return nil
        }
        return Range(match.range, in: source)
    }

    private static let nonCodePrefixes = ["//", "/*", "*", "#!"]

    private static func isCodeLine(_ trimmed: String) -> Bool {
        !trimmed.isEmpty && !nonCodePrefixes.contains(where: trimmed.hasPrefix)
    }

    /// 주석과 문자열을 같은 UTF-16 길이의 공백으로 치환한 코드 뷰.
    /// 줄바꿈은 보존하므로 줄 번호·`NSRange` 가 원문과 맞는다.
    static func stripCommentsAndStrings(_ source: String) -> String {
        SourceCommentStringMasker.mask(source)
    }
}
