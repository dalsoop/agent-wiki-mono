import Foundation

/// 화이트리스트 / 무시 규칙 거버넌스
public struct IgnoreEntry: Codable, Sendable, Identifiable {
    public var id: String { pattern }
    public let pattern: String
    public let reason: String
    public let addedAt: Date

    public init(pattern: String, reason: String = "Whitelisted", addedAt: Date = Date()) {
        self.pattern = pattern
        self.reason = reason
        self.addedAt = addedAt
    }
}

public struct IgnoreConfigFile: Codable, Sendable {
    public var ignoredPatterns: [IgnoreEntry]

    public init(ignoredPatterns: [IgnoreEntry] = []) {
        self.ignoredPatterns = ignoredPatterns
    }
}

public enum IgnoreGovernance {
    /// 앱 루트 디렉터리의 `.unused-ignore.json` 파일을 로드한다.
    public static func loadIgnoreFile(appRoot: URL) -> IgnoreConfigFile {
        let configURL = appRoot.appendingPathComponent(".unused-ignore.json")
        guard let data = try? Data(contentsOf: configURL),
              let file = try? JSONDecoder().decode(IgnoreConfigFile.self, from: data) else {
            return IgnoreConfigFile()
        }
        return file
    }

    /// 심볼 또는 파일명이 무시 규칙에 해당하는지 검사
    public static func isIgnored(symbolOrName: String, in config: IgnoreConfigFile) -> (ignored: Bool, reason: String?) {
        for entry in config.ignoredPatterns {
            if entry.pattern == symbolOrName || matchWildcard(pattern: entry.pattern, text: symbolOrName) {
                return (true, entry.reason)
            }
        }
        return (false, nil)
    }

    /// 간단한 와일드카드 매칭 (예: `*_mock`, `Test*`)
    public static func matchWildcard(pattern: String, text: String) -> Bool {
        if pattern == "*" { return true }
        if pattern.hasPrefix("*") && pattern.hasSuffix("*") && pattern.count > 2 {
            let middle = pattern.dropFirst().dropLast()
            return text.contains(middle)
        }
        if pattern.hasPrefix("*") {
            let suffix = pattern.dropFirst()
            return text.hasSuffix(suffix)
        }
        if pattern.hasSuffix("*") {
            let prefix = pattern.dropLast()
            return text.hasPrefix(prefix)
        }
        return pattern == text
    }
}
