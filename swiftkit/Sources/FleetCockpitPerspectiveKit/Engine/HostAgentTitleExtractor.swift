import Foundation

/// 서브에이전트 프로세스 및 커맨드라인에서 유의미한 작업 제목을 추출하는 순수 유틸리티
public enum HostAgentTitleExtractor: Sendable {

    // 정적 정규식 캐시 (컴파일 성공 보장 패턴)
    private static let worktreeRegex: NSRegularExpression? = {
        do {
            return try NSRegularExpression(pattern: #"(?:^|[\s/])\.worktrees/([a-zA-Z0-9_\-]+)"#, options: [])
        } catch {
            return nil
        }
    }()

    private static let promptRegexList: [NSRegularExpression] = {
        let patterns = [
            #"(?:--prompt|-p|--task|-m|--title)\s+["']([^"']+)["']"#,
            #"(?:--prompt|-p|--task|-m|--title)\s+([^\s\-]+)"#
        ]
        var list: [NSRegularExpression] = []
        for pat in patterns {
            do {
                let rx = try NSRegularExpression(pattern: pat, options: [])
                list.append(rx)
            } catch {
                continue
            }
        }
        return list
    }()

    private static let quoteRegex: NSRegularExpression? = {
        do {
            return try NSRegularExpression(pattern: #"["']([^"'\n]{2,50})["']"#, options: [])
        } catch {
            return nil
        }
    }()

    private static let scriptRegex: NSRegularExpression? = {
        do {
            return try NSRegularExpression(pattern: #"([a-zA-Z0-9_\-]+\.(?:sh|py|js|ts|rb|swift|tool))"#, options: [])
        } catch {
            return nil
        }
    }()

    public static func extractSubagentTitle(command: String, cwd: String? = nil) -> String {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "subagent" }

        // 1. worktree 경로 패턴 검사 (.worktrees/<이름>)
        if let wtTitle = extractWorktreeTitle(from: trimmed) {
            return wtTitle
        }

        // 2. 프롬프트 또는 작업 명칭 추출 (--prompt, -p, --task, -m 등)
        if let promptTitle = extractPromptTitle(from: trimmed) {
            return promptTitle
        }

        // 3. 따옴표로 감싸진 의미 있는 프롬프트 텍스트
        if let quoteTitle = extractQuoteTitle(from: trimmed) {
            return quoteTitle
        }

        // 4. sh -c / bash -c / zsh -c 래퍼 명령어 파싱
        if let wrapped = extractWrappedShellCommand(from: trimmed, cwd: cwd) {
            return wrapped
        }

        // 5. 스크립트 실행 파일명 (.sh, .py, .js 등)
        if let scriptName = extractScriptFilename(from: trimmed) {
            return scriptName
        }

        // 6. cwd 기반 worktree 추출
        if let cwdTitle = extractCWDWorktree(from: cwd) {
            return cwdTitle
        }

        // 7. 일반 CLI 명령어 축약 요약
        return extractCLICommandSummary(from: trimmed)
    }

    private static func extractWorktreeTitle(from trimmed: String) -> String? {
        guard let regex = worktreeRegex else { return nil }
        let ns = trimmed as NSString
        let matches = regex.matches(in: trimmed, range: NSRange(location: 0, length: ns.length))
        guard let match = matches.first, match.numberOfRanges > 1 else { return nil }
        let range = match.range(at: 1)
        let extracted = ns.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
        return extracted.isEmpty ? nil : extracted
    }

    private static func extractPromptTitle(from trimmed: String) -> String? {
        let ns = trimmed as NSString
        for regex in promptRegexList {
            let matches = regex.matches(in: trimmed, range: NSRange(location: 0, length: ns.length))
            guard let match = matches.first, match.numberOfRanges > 1 else { continue }
            let extracted = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !extracted.isEmpty else { continue }

            let isShortOrDigits = extracted.allSatisfy(\.isNumber) || extracted.count <= 2
            if isShortOrDigits {
                let prefix = summarizeCommandPrefix(trimmed)
                return "\(prefix) (\(extracted))"
            }
            let firstLine = extracted.split(separator: "\n").first.map(String.init) ?? extracted
            return firstLine.count > 40 ? String(firstLine.prefix(37)) + "..." : firstLine
        }
        return nil
    }

    private static func extractQuoteTitle(from trimmed: String) -> String? {
        guard let regex = quoteRegex else { return nil }
        let ns = trimmed as NSString
        let matches = regex.matches(in: trimmed, range: NSRange(location: 0, length: ns.length))
        for match in matches where match.numberOfRanges > 1 {
            let extracted = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            let isFlagOrPath = extracted.hasPrefix("-") || extracted.hasPrefix("/")
            guard !isFlagOrPath && !extracted.isEmpty else { continue }
            return extracted.count > 40 ? String(extracted.prefix(37)) + "..." : extracted
        }
        return nil
    }

    private static func extractWrappedShellCommand(from trimmed: String, cwd: String?) -> String? {
        guard let shRange = trimmed.range(of: #"(?:^|[\s/])(?:sh|bash|zsh)\s+-c\s+["']?([^"']+)["']?"#, options: .regularExpression) else {
            return nil
        }
        let sub = trimmed[shRange]
        let tokens = sub.split(separator: " ", maxSplits: 2)
        guard tokens.count >= 3 else { return nil }
        let inner = String(tokens[2]).trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
        guard !inner.isEmpty, inner != trimmed else { return nil }
        return extractSubagentTitle(command: inner, cwd: cwd)
    }

    private static func extractScriptFilename(from trimmed: String) -> String? {
        guard let regex = scriptRegex else { return nil }
        let ns = trimmed as NSString
        let matches = regex.matches(in: trimmed, range: NSRange(location: 0, length: ns.length))
        guard let match = matches.first, match.numberOfRanges > 1 else { return nil }
        return ns.substring(with: match.range(at: 1))
    }

    private static func extractCWDWorktree(from cwd: String?) -> String? {
        guard let cwd, !cwd.isEmpty else { return nil }
        let hasWorktree = cwd.contains(".worktrees/") || cwd.contains("/worktrees/")
        guard hasWorktree else { return nil }
        return URL(fileURLWithPath: cwd).lastPathComponent
    }

    private static func extractCLICommandSummary(from trimmed: String) -> String {
        let tokens = trimmed.split(separator: " ").map(String.init)
        guard !tokens.isEmpty else { return "subagent" }

        var clean = tokens
        let first = URL(fileURLWithPath: clean[0]).lastPathComponent
        let isShell = (first == "sh" || first == "bash" || first == "zsh" || first == "login")
        if isShell {
            clean.removeFirst()
            if clean.first == "-c" || clean.first == "-l" {
                clean.removeFirst()
            }
        }
        guard !clean.isEmpty else { return "subagent" }

        var summary = URL(fileURLWithPath: clean[0]).lastPathComponent
        for tok in clean.dropFirst().prefix(3) {
            let include = !tok.hasPrefix("-") || tok.hasPrefix("--task") || tok.hasPrefix("-p")
            if include {
                summary += " \(tok)"
            }
        }
        return summary.count > 40 ? String(summary.prefix(37)) + "..." : summary
    }

    public static func summarizeCommandPrefix(_ command: String) -> String {
        let tokens = command.split(separator: " ").map(String.init)
        guard let first = tokens.first else { return "agent" }
        let bin = URL(fileURLWithPath: first).lastPathComponent
        let isShell = (bin == "sh" || bin == "bash" || bin == "zsh")
        if isShell, tokens.count > 2, tokens[1] == "-c" {
            let sub = tokens[2].trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            let subTokens = sub.split(separator: " ")
            if let subFirst = subTokens.first {
                return URL(fileURLWithPath: String(subFirst)).lastPathComponent
            }
        }
        if tokens.count > 1 && !tokens[1].hasPrefix("-") {
            return "\(bin) \(tokens[1])"
        }
        return bin
    }
}
