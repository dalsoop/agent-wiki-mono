import Foundation

/// CLI 소스를 prelude / 파일 스코프 선언 / 본문으로 나눈다.
enum CLISourcePartitioner {
    struct Partition {
        var prelude: [String]
        var fileScope: [String]
        var body: [String]
    }

    /// 본문만 `runWithUniversalError` 로 감싼다. 인식 실패 또는 본문 없음이면 `nil`.
    static func wrapBody(_ source: String, guards: [String]) -> String? {
        guard let partition = partition(source), !partition.body.isEmpty else {
            return nil
        }
        return render(partition, guards: guards)
    }

    static func partition(_ source: String) -> Partition? {
        let originalLines = source.components(separatedBy: "\n")
        let maskedLines = SourceTransformerHelper.stripCommentsAndStrings(source).components(separatedBy: "\n")
        guard originalLines.count == maskedLines.count else {
            return nil
        }
        return scanLines(originalLines: originalLines, maskedLines: maskedLines)
    }
}

private extension CLISourcePartitioner {
    static func scanLines(originalLines: [String], maskedLines: [String]) -> Partition? {
        var prelude: [String] = []
        var fileScope: [String] = []
        var body: [String] = []
        var pending: [String] = []
        var index = 0

        while index < originalLines.count {
            let masked = maskedLines[index].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !masked.isEmpty else {
                pending.append(originalLines[index])
                index += 1
                continue
            }
            guard let span = classifySpan(originalLines: originalLines, maskedLines: maskedLines, start: index) else {
                return nil
            }
            let chunk = pending + Array(originalLines[span.start..<span.end])
            pending = []
            appendChunk(chunk, region: span.region, prelude: &prelude, fileScope: &fileScope, body: &body)
            index = span.end
        }

        trimTrailingEmpty(&prelude)
        trimLeadingAndTrailingEmpty(&fileScope)
        trimLeadingAndTrailingEmpty(&body)
        return Partition(prelude: prelude, fileScope: fileScope, body: body)
    }

    static func appendChunk(
        _ chunk: [String],
        region: CLISourceLineKind,
        prelude: inout [String],
        fileScope: inout [String],
        body: inout [String]
    ) {
        switch region {
        case .prelude:
            prelude.append(contentsOf: chunk)
        case .fileScope:
            fileScope.append(contentsOf: chunk)
        case .body:
            body.append(contentsOf: chunk)
        case .ifDirective:
            body.append(contentsOf: chunk)
        }
    }

    static func classifySpan(
        originalLines: [String],
        maskedLines: [String],
        start: Int
    ) -> (region: CLISourceLineKind, start: Int, end: Int)? {
        let masked = maskedLines[start].trimmingCharacters(in: .whitespaces)
        switch CLISourceLineKind.classify(masked) {
        case .ifDirective:
            return classifyIfBlock(originalLines: originalLines, maskedLines: maskedLines, start: start)
        case .prelude:
            return (.prelude, start, start + 1)
        case .fileScope:
            return balancedSpan(maskedLines: maskedLines, start: start, region: .fileScope)
        case .body:
            return balancedSpan(maskedLines: maskedLines, start: start, region: .body)
        case nil:
            return nil
        }
    }

    static func balancedSpan(
        maskedLines: [String],
        start: Int,
        region: CLISourceLineKind
    ) -> (region: CLISourceLineKind, start: Int, end: Int)? {
        guard let end = CLISourceBalance.consume(maskedLines: maskedLines, start: start) else {
            return nil
        }
        return (region, start, end)
    }

    static func classifyIfBlock(
        originalLines: [String],
        maskedLines: [String],
        start: Int
    ) -> (region: CLISourceLineKind, start: Int, end: Int)? {
        guard let end = matchingEndif(maskedLines: maskedLines, start: start) else {
            return nil
        }
        guard let region = regionsInsideIf(
            originalLines: originalLines,
            maskedLines: maskedLines,
            start: start,
            end: end
        ) else {
            return nil
        }
        return (region, start, end)
    }

    static func regionsInsideIf(
        originalLines: [String],
        maskedLines: [String],
        start: Int,
        end: Int
    ) -> CLISourceLineKind? {
        var regions = Set<CLISourceLineKind>()
        var cursor = start + 1
        while cursor < end {
            let inner = maskedLines[cursor].trimmingCharacters(in: .whitespacesAndNewlines)
            if shouldSkipIfInner(inner) {
                cursor += 1
                continue
            }
            guard let span = classifySpan(originalLines: originalLines, maskedLines: maskedLines, start: cursor),
                  span.end <= end else {
                return nil
            }
            regions.insert(span.region)
            cursor = span.end
        }
        return collapseRegions(regions)
    }

    static func shouldSkipIfInner(_ inner: String) -> Bool {
        inner.isEmpty || CLISourceLineKind.isConditionalDirective(inner)
    }

    static func collapseRegions(_ regions: Set<CLISourceLineKind>) -> CLISourceLineKind? {
        let meaningful = regions.subtracting([.ifDirective])
        if meaningful.isEmpty {
            return .prelude
        }
        guard meaningful.count == 1 else {
            return nil
        }
        return meaningful.first
    }

    static func matchingEndif(maskedLines: [String], start: Int) -> Int? {
        var depth = 0
        var index = start
        while index < maskedLines.count {
            depth = updateIfDepth(depth, line: maskedLines[index])
            if isClosedEndif(depth: depth, line: maskedLines[index]) {
                return index + 1
            }
            index += 1
        }
        return nil
    }

    static func updateIfDepth(_ depth: Int, line: String) -> Int {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("#if") {
            return depth + 1
        }
        if trimmed.hasPrefix("#endif") {
            return depth - 1
        }
        return depth
    }

    static func isClosedEndif(depth: Int, line: String) -> Bool {
        depth == 0 && line.trimmingCharacters(in: .whitespaces).hasPrefix("#endif")
    }

    static func trimTrailingEmpty(_ lines: inout [String]) {
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.removeLast()
        }
    }

    static func trimLeadingAndTrailingEmpty(_ lines: inout [String]) {
        while let first = lines.first, first.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.removeFirst()
        }
        trimTrailingEmpty(&lines)
    }

    static func render(_ partition: Partition, guards: [String]) -> String {
        var lines = partition.prelude
        appendFileScope(&lines, partition.fileScope)
        appendWrapper(&lines, body: partition.body, guards: guards)
        return lines.joined(separator: "\n")
    }

    static func appendFileScope(_ lines: inout [String], _ fileScope: [String]) {
        guard !fileScope.isEmpty else { return }
        appendBlankIfNeeded(&lines)
        lines.append(contentsOf: fileScope)
    }

    static func appendWrapper(_ lines: inout [String], body: [String], guards: [String]) {
        appendBlankIfNeeded(&lines)
        lines.append("runWithUniversalError {")
        lines.append(contentsOf: guards)
        appendGuardBodySeparator(&lines, guards: guards, body: body)
        lines.append(contentsOf: indented(body))
        lines.append("}")
        lines.append("")
    }

    static func appendGuardBodySeparator(_ lines: inout [String], guards: [String], body: [String]) {
        guard !guards.isEmpty, !body.isEmpty else { return }
        lines.append("")
    }

    static func appendBlankIfNeeded(_ lines: inout [String]) {
        guard !lines.isEmpty else { return }
        lines.append("")
    }

    static func indented(_ body: [String]) -> [String] {
        body.map { line in
            line.isEmpty ? "" : "    " + line
        }
    }
}
